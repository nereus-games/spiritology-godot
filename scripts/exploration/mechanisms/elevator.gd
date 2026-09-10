## An elevator: a platform that sets off the moment you step on it, runs its predefined path in
## ONE turn, and returns to its starting point when you step on it a second time. From the design
## doc ("Mechanisms / Elevators").
##
## The path is a SEQUENCE OF WAYPOINTS in absolute cells ([member path]): the doc says "a
## predefined path" without restricting it to the vertical. An elevator can therefore go straight
## up, slide horizontally, or chain segments along all three axes. Only the TWO ENDS — the start
## and the last point — matter logically; the intermediate points just draw the trajectory, and
## may pass over empty space.
##
## The platform genuinely MOVES: its cell changes, so it re-registers with the [DungeonManager]
## on every trip. Both ENDS have to be FLOOR cells — this mechanism digs no hole behind it, and
## the shaft is level design's business.
##
## The trip costs no extra turn: the step onto the platform already spent one, and the design doc
## says the trip fits "in one turn".
##
## No `class_name`: `extends` by path.
extends "res://scripts/exploration/mechanisms/dungeon_mechanism.gd"

## Waypoints AFTER the starting cell, in ABSOLUTE cells. The last one is the far end of the trip
## and has to be floor. A single point means a direct trip, such as a purely vertical one.
@export var path: Array[Vector3i] = []

## How long ONE segment takes seen from outside — an empty platform, or one carrying a rival.
## Per segment rather than for the whole trip: a complicated route should take longer than a
## straight vertical one, otherwise it plays back faster the more it has to show.
@export var segment_duration := 0.5

## How long ONE segment takes with THE PLAYER aboard. Markedly slower: from outside you only
## register that a platform is moving, but aboard you read the route — and on a path that goes
## sideways before climbing, you need time to see where it leads.
@export var rider_segment_duration := 1.2

var _origin: Vector3i
var _at_far_end := false
var _moving := false


func _on_registered() -> void:
	_origin = cell
	if path.is_empty():
		push_warning("[Elevator] at %s: no path set." % cell)


## The far end of the trip: the last waypoint on the way out, the starting cell on the way back.
func far_end() -> Vector3i:
	if path.is_empty():
		return cell
	return _origin if _at_far_end else path[path.size() - 1]


## The points to travel through, in order, to reach the far end from the current position.
func _route() -> Array:
	if path.is_empty():
		return []
	if _at_far_end:
		# On the way back, walk the intermediate points in reverse, then return to the start.
		var back: Array = []
		for i in range(path.size() - 2, -1, -1):
			back.append(path[i])
		back.append(_origin)
		return back
	return path.duplicate()


## Stepping on it is enough to set it off, per the design doc. True for rivals as well as the
## player: the doc's "Rivals" page wants a rival to follow the player by any means that costs no
## DEN.
func on_enter(who: Node) -> void:
	ride(who)


## Takes `who` and the platform to the far end. Returns the destination cell, or the current one
## when the trip could not happen.
func ride(who: Node) -> Vector3i:
	var route := _route()
	if _moving or _dungeon == null or route.is_empty():
		return cell
	var dest: Vector3i = route[route.size() - 1]
	if dest == cell:
		return cell
	if not _dungeon.is_floor(dest):
		push_warning("[Elevator] %s -> %s: the destination is not floor." % [cell, dest])
		return cell
	var from := cell
	_moving = true
	_dungeon.unregister_mechanism(from, self)
	cell = dest
	_dungeon.register_mechanism(cell, self)
	_at_far_end = not _at_far_end
	# The platform and its rider must move at the SAME rate or the rider would lift off, so
	# whether the player is aboard sets the speed of the whole thing.
	var per_segment: float = rider_segment_duration if _dungeon.is_player(who) else segment_duration
	_carry(who, from, dest, route, per_segment)
	var tween := _travel_tween(self, route, per_segment)
	tween.finished.connect(func() -> void: _moving = false)
	return dest


## Chains a move along `route`, at `per_segment` seconds per waypoint.
func _travel_tween(node: Node3D, route: Array, per_segment: float) -> Tween:
	var tween := node.create_tween()
	for wp in route:
		tween.tween_property(node, "global_position", _dungeon.cell_to_world(wp), per_segment)
	return tween


## Carries the rider along with the platform: its cell changes at once, since the turn logic
## depends on it, but its body follows the trajectory instead of teleporting.
func _carry(who: Node, from: Vector3i, dest: Vector3i, route: Array, per_segment: float) -> void:
	if who == null or not who.has_method("teleport_to"):
		return
	# A rival occupies a cell and the player does not, so occupancy follows the rider.
	if not _dungeon.is_player(who):
		_dungeon.release(from)
		_dungeon.reserve(dest, who)
	# Watching rivals may decide to follow, per the design doc's "Rivals".
	_dungeon.notify_level_change(who, from, dest)
	who.teleport_to(dest)
	who.global_position = _dungeon.cell_to_world(from)  # back to the start, for the animation
	var locked: bool = "input_locked" in who
	if locked:
		who.input_locked = true
	var tween := _travel_tween(who, route, per_segment)
	tween.finished.connect(
		func() -> void:
			if locked and is_instance_valid(who):
				who.input_locked = false
	)


# --- Floor changes (the common interface; see DungeonMechanism) ---


## A purely HORIZONTAL elevator links no two floors, and is then useless to a chasing rival,
## which can just walk.
func has_level_link() -> bool:
	return far_end().y != cell.y


## An elevator is taken by STEPPING ON IT, so the cell it is taken from is the platform
## itself.
func level_link_from() -> Vector3i:
	return cell


func level_link_to() -> Vector3i:
	return far_end()


## Nothing to step "into": arriving on the platform is enough (see [method on_enter]).
func level_link_needs_step_in() -> bool:
	return false


## The platform: a thick slab resting on the cell's floor, brightly coloured to be spotted.
func _spawn_visual() -> void:
	_add_marker_box(Color(0.85, 0.62, 0.20), Vector3(0.9, 0.12, 0.9))
