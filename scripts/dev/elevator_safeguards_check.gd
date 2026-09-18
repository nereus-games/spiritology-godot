## Headless check of the design doc's safeguards for areas reached by elevator ("Mechanisms /
## Elevators" and "Gateways"): linked elevators, teleport gates, safe areas. Walks the
## "elevator_safeguards" scenario for what the player sees, then a bare dungeon for the rule that
## pushes a rival group aside when another arrives on its tile.
##
## Run with: Godot --headless --path . res://scenes/dev/elevator_safeguards_check.tscn
## As a start scene rather than --script; see geometry_check.gd.
extends Node

const ScenarioCatalog := preload("res://scripts/dev/scenario_catalog.gd")
const EXPLORATION := preload("res://scenes/exploration/exploration.tscn")
const RIVAL_SCENE := preload("res://scenes/exploration/rival/rival.tscn")
const Trap := preload("res://scripts/exploration/mechanisms/trap.gd")
const Gateway := preload("res://scripts/exploration/mechanisms/gateway.gd")

## Tiles of the scenario, as `ScenarioCatalog._elevator_safeguards` lays them out.
const WEST_LOWER := Vector3i(1, 0, 8)
const WEST_UPPER := Vector3i(2, 2, 8)
const MIDDLE_GATE := Vector3i(7, 2, 10)
const MIDDLE_ARRIVAL := Vector3i(7, 0, 3)
const EAST_LIFT := Vector3i(12, 0, 8)
const HALL_GATE_WEST := Vector3i(3, 0, 3)
const HALL_GATE_EAST := Vector3i(4, 0, 3)
const HALL_ARRIVAL := Vector3i(14, 0, 0)

var _fails: Array[String] = []
## Encounters the dungeon asked for, as [rival, initiated_by_rival].
var _encounters: Array = []


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  OK   %s" % label)
	else:
		print("  FAIL %s" % label)
		_fails.append(label)


func _ready() -> void:
	_run_all()


func _run_all() -> void:
	await get_tree().process_frame
	var ctx := await _setup()
	print("[linked elevators]")
	await _check_linked(ctx.dm, ctx.player)
	print("[teleport gates]")
	await _check_wall_gate(ctx.dm, ctx.player)
	await _check_two_sided_gate(ctx.dm, ctx.player)
	await _check_rival_through_gate(ctx.dm, ctx.player)
	print("[safe area]")
	await _check_safe_area(ctx.dm, ctx.player)
	ctx.scene.queue_free()
	await get_tree().process_frame
	print("[pushing a group aside]")
	await _check_push_ordinary()
	await _check_push_onto_trap()
	await _check_push_over_ledge()
	await _check_push_chain()
	print("")
	if _fails.is_empty():
		print("ALL OK")
	else:
		print("FAILURES: %s" % [_fails])
	get_tree().quit(0 if _fails.is_empty() else 1)


# --------------------------------------------------------------------------
# The scenario
# --------------------------------------------------------------------------


## Builds the scenario with encounters captured rather than opened, instant elevators, and the
## scenario's own rival taken out — it wanders, and every check below places the rivals it needs.
func _setup() -> Dictionary:
	ScenarioCatalog.selected_id = &"elevator_safeguards"
	var scene = EXPLORATION.instantiate()
	get_tree().root.add_child(scene)
	await get_tree().process_frame
	var dm = scene.get_node("DungeonManager")
	var player = scene.get_node("Player")
	dm.encounter_requested.disconnect(scene._on_encounter_requested)
	dm.encounter_requested.connect(
		func(rival: Node, by_rival: bool) -> void: _encounters.append([rival, by_rival])
	)
	player.move_duration = 0.01
	for m in dm.get_children():
		if m.has_method("ride"):
			m.segment_duration = 0.0
			m.rider_segment_duration = 0.0
	var rivals: Array = dm.rivals()
	_check(rivals.size() == 1, "one rival in the hall")
	for r in rivals:
		r.remove_from_dungeon()
	await get_tree().process_frame
	return {"scene": scene, "dm": dm, "player": player}


func _spawn_rival(dm, tile: Vector3i) -> Node:
	var r = RIVAL_SCENE.instantiate()
	r.position = dm.tile_to_world(tile)
	dm.add_child(r)
	return r


func _elevator_at(dm, tile: Vector3i) -> Node:
	for m in dm.mechanisms_at(tile):
		if m.has_method("ride"):
			return m
	return null


## Puts the player on a platform, the way stepping onto it does.
func _step_on(dm, player, tile: Vector3i) -> void:
	player.teleport_to(tile)
	dm.notify_entered(tile, player)
	await get_tree().process_frame


## Stepping onto one platform moves its twin the other way, so whichever end the player is
## stranded at — after jumping off the top — a platform is waiting there. The twin moves EMPTY.
func _check_linked(dm, player) -> void:
	var lower = _elevator_at(dm, WEST_LOWER)
	var upper = _elevator_at(dm, WEST_UPPER)
	_check(lower != null and upper != null, "two platforms in the west area")
	if lower == null or upper == null:
		return
	_check(upper in lower.linked and lower in upper.linked, "linked both ways")
	var top: Vector3i = lower.far_end()
	var bottom: Vector3i = upper.far_end()

	await _step_on(dm, player, lower.tile)
	_check(player.tile == top and lower.tile == top, "the lower platform carries the player up")
	_check(upper.tile == bottom, "its twin came down at the same time (%s)" % upper.tile)

	# Stranded: the player leaves the area by jumping off, and the platform they rode stays up.
	player.teleport_to(Vector3i(1, 0, 6))
	var waiting := []
	for m in [lower, upper]:
		if m.tile.y == 0 and m.far_end().y == 2:
			waiting.append(m)
	_check(waiting.size() == 1, "after a fall, a platform is waiting at the bottom")

	await _step_on(dm, player, upper.tile)
	_check(player.tile == WEST_UPPER, "the twin takes the player back up")
	_check(lower.tile == WEST_LOWER, "and the first platform is back down (%s)" % lower.tile)

	# A rival standing on the twin stays behind when the twin is moved by the link.
	var rival := _spawn_rival(dm, lower.tile)
	await get_tree().process_frame
	await _step_on(dm, player, upper.tile)
	_check(lower.tile == top, "the linked platform went up without being stepped on")
	_check(
		rival.tile == WEST_LOWER and dm.occupant_at(WEST_LOWER) == rival,
		"it went up EMPTY: the rival on it stayed on the floor (%s)" % rival.tile
	)
	rival.remove_from_dungeon()
	await get_tree().process_frame


## Sets a gate open or closed by ticking it on a turn of the pattern that gives that state.
func _set_open(gate, open: bool) -> void:
	for t in gate.open_pattern.size():
		gate.on_turn(t)
		if gate.is_open() == open:
			return


## The gate set against the back wall of the middle area: never a passage, open only on its
## pattern, one way, and entered from its open side only.
func _check_wall_gate(dm, player) -> void:
	var beyond := MIDDLE_GATE + Vector3i(0, 0, 1)
	var gate = Gateway.teleport_gate_between(dm, MIDDLE_GATE, beyond)
	_check(gate != null, "a teleport gate on the middle area's back wall")
	if gate == null:
		return
	_check(dm.mechanisms_at(MIDDLE_GATE).is_empty(), "a teleport gate occupies no tile")
	_check(dm.derive_wall_tiles().has(beyond), "it stands against a wall")
	var p: Array = gate.open_pattern
	_check(
		p.size() == 3 and not p[0] and not p[1] and p[2], "default pattern: closed, closed, open"
	)
	_check(gate.arrival_tile.y == 0, "it leads out of the area, down to the hall")

	_set_open(gate, false)
	_check(dm.is_edge_blocked(MIDDLE_GATE, beyond), "closed: the edge is blocked")
	player.teleport_to(MIDDLE_GATE)
	await player.try_move(Vector3.FORWARD)
	_check(player.tile == MIDDLE_GATE, "closed: walking into it does nothing")

	_set_open(gate, true)
	_check(dm.is_edge_blocked(MIDDLE_GATE, beyond), "open: still no passage across")
	_check(dm.is_edge_opaque(MIDDLE_GATE, beyond), "open: nothing to see through it")
	_check(not gate.admits_from(beyond), "not entered from the wall side")
	var turn_before: int = dm.turn_count
	await player.try_move(Vector3.FORWARD)
	_check(player.tile == MIDDLE_ARRIVAL, "open: going through lands on its arrival tile")
	_check(dm.turn_count == turn_before + 1, "going through costs one turn, like a step")
	_check(
		(
			Gateway.teleport_gate_between(dm, MIDDLE_ARRIVAL, MIDDLE_ARRIVAL + Vector3i(0, 0, 1))
			== null
		),
		"no gate at the arrival: the trip is one way"
	)

	# Arriving on a rival: the teleport happens anyway, and so does an encounter.
	var rival := _spawn_rival(dm, MIDDLE_ARRIVAL)
	await get_tree().process_frame
	_encounters.clear()
	player.teleport_to(MIDDLE_GATE)
	_set_open(gate, true)
	await player.try_move(Vector3.FORWARD)
	_check(player.tile == MIDDLE_ARRIVAL, "arriving on a rival: the player still arrives")
	_check(
		_encounters.size() == 1 and _encounters[0][0] == rival and not _encounters[0][1],
		"arriving on a rival starts an encounter, started by the player"
	)
	rival.remove_from_dungeon()
	await get_tree().process_frame


## The hall's gate stands between two floor tiles: it bars the step between them for good, and
## from either side leads to the same arrival.
func _check_two_sided_gate(dm, player) -> void:
	var gate = Gateway.teleport_gate_between(dm, HALL_GATE_WEST, HALL_GATE_EAST)
	_check(gate != null and gate.two_sided, "a two-sided teleport gate in the hall")
	if gate == null:
		return
	_set_open(gate, true)
	_check(
		(
			not dm.can_step(HALL_GATE_WEST, HALL_GATE_EAST)
			and not dm.can_step(HALL_GATE_EAST, HALL_GATE_WEST)
		),
		"open, it still blocks the step between its two tiles, both ways"
	)
	# The player faces +z: LEFT is +x, RIGHT is -x.
	player.teleport_to(HALL_GATE_WEST)
	await player.try_move(Vector3.LEFT)
	_check(player.tile == HALL_ARRIVAL, "entered from the west: the far corner")
	_set_open(gate, true)
	player.teleport_to(HALL_GATE_EAST)
	await player.try_move(Vector3.RIGHT)
	_check(player.tile == HALL_ARRIVAL, "entered from the east: the same far corner")


## Rivals go through open gates on their own moves, and arriving on the player starts an
## encounter.
func _check_rival_through_gate(dm, player) -> void:
	var gate = Gateway.teleport_gate_between(dm, MIDDLE_GATE, MIDDLE_GATE + Vector3i(0, 0, 1))
	var rival := _spawn_rival(dm, MIDDLE_GATE)
	await get_tree().process_frame
	# Heading for the wall behind the gate, from memory — the player is on another storey.
	player.teleport_to(MIDDLE_ARRIVAL)
	rival._target_tile = MIDDLE_GATE + Vector3i(0, 0, 1)
	rival._has_target = true
	rival._memory = 5
	_encounters.clear()
	_set_open(gate, false)
	await rival.take_turn(player.tile)
	_check(rival.tile == MIDDLE_GATE, "a closed gate stops a rival")
	_set_open(gate, true)
	await rival.take_turn(player.tile)
	_check(rival.tile == MIDDLE_ARRIVAL, "an open gate sends a rival to its arrival tile")
	_check(dm.occupant_at(MIDDLE_ARRIVAL) == rival, "and it occupies the tile it arrived on")
	_check(dm.occupant_at(MIDDLE_GATE) == null, "and no longer the one it left")
	_check(
		_encounters.size() == 1 and _encounters[0][0] == rival and _encounters[0][1],
		"a rival arriving on the player starts an encounter, started by the rival"
	)
	rival.remove_from_dungeon()
	await get_tree().process_frame


## The safe area holds by construction, keeps rivals out whatever way they would come in, and
## the report of what breaks one does report it.
func _check_safe_area(dm, player) -> void:
	_check(dm.safe_areas.tiles().size() == 16, "16 safe tiles")
	var faults: Array = dm.safe_areas.violations()
	_check(faults.is_empty(), "nothing in the safe area breaks it (%s)" % [faults])

	var lift = _elevator_at(dm, EAST_LIFT)
	_check(lift != null and dm.safe_areas.has(lift.far_end()), "an elevator serves the safe area")
	_check(not dm.safe_areas.rival_may_enter(EAST_LIFT), "a rival may not step onto its platform")

	# A rival chasing the player up to the safe area does not take its elevator.
	player.teleport_to(lift.far_end())
	var rival := _spawn_rival(dm, EAST_LIFT + Vector3i(0, 0, -1))
	await get_tree().process_frame
	rival._target_tile = EAST_LIFT + Vector3i(0, 0, 1)
	rival._has_target = true
	rival._memory = 5
	await rival.take_turn(player.tile)
	_check(rival.tile == EAST_LIFT + Vector3i(0, 0, -1), "the rival stops short of the platform")
	_check(lift.tile == EAST_LIFT, "and the platform stays down")
	var link: Node = rival._nearest_level_link(1)
	_check(
		link != null and not dm.safe_areas.has(link.level_link_to()),
		"the rival's way up is some other elevator"
	)
	# Next to the safe area, across an edge with no rail, a rival sees the player and does not
	# walk in to meet them.
	rival.remove_from_dungeon()
	await get_tree().process_frame
	var edge := Vector3i(11, 2, 11)
	dm.add_floor(edge)  # a tile beyond the back wall, just for this
	var guard := _spawn_rival(dm, edge)
	await get_tree().process_frame
	player.teleport_to(Vector3i(11, 2, 10))
	_encounters.clear()
	await guard.take_turn(player.tile)
	_check(_encounters.is_empty(), "no encounter started from outside the safe area")
	guard.remove_from_dungeon()
	dm._floor.erase(edge)
	await get_tree().process_frame

	var landed_safe := false
	for i in 200:
		if dm.safe_areas.has(dm.random_floor_tile(EAST_LIFT, true)):
			landed_safe = true
	_check(not landed_safe, "a teleport trap never drops a rival in the safe area")

	# The report catches what level design might get wrong.
	var trap = Trap.new()
	trap.position = dm.tile_to_world(Vector3i(13, 2, 9))
	dm.add_child(trap)
	_check(dm.safe_areas.violations().size() == 1, "a trap in the safe area is reported")
	dm.remove_child(trap)
	trap.free()
	var rail: Node = dm.edge_mechanisms_between(Vector3i(11, 2, 9), Vector3i(10, 2, 9))[0]
	dm.remove_child(rail)
	faults = dm.safe_areas.violations()
	_check(faults.size() == 1, "an unrailed ledge is reported (%s)" % [faults])
	rail.free()


# --------------------------------------------------------------------------
# Pushing a group aside, in a bare dungeon
# --------------------------------------------------------------------------


## A bare dungeon: floor on `tiles`, no player, nothing else. Freed by [method _drop_field].
func _field(tiles: Array) -> DungeonManager:
	var dm := DungeonManager.new()
	add_child(dm)
	for t in tiles:
		dm.add_floor(t)
	return dm


func _drop_field(dm) -> void:
	dm.queue_free()
	await get_tree().process_frame


## A group arriving through a gate onto `at`, from `from`: returns [newcomer, the one there]. The
## gate stands on `from`'s edge towards +x, where nothing else is.
func _arrive(dm, from: Vector3i, at: Vector3i) -> Array:
	var gate = Gateway.new()
	gate.kind = Gateway.Kind.TELEPORT
	gate.edge_dir = Vector3i(1, 0, 0)
	gate.arrival_tile = at
	gate.position = dm.tile_to_world(from)
	dm.add_child(gate)
	var there := _spawn_rival(dm, at)
	var newcomer := _spawn_rival(dm, from)
	await get_tree().process_frame
	gate.send_through(newcomer)
	return [newcomer, there]


func _is_neighbour(a: Vector3i, b: Vector3i) -> bool:
	var d := (a - b).abs()
	return d.y == 0 and d.x + d.z == 1


func _check_push_ordinary() -> void:
	var at := Vector3i(11, 0, 11)
	var trapped := Vector3i(12, 0, 11)
	var dm := _field([at, trapped, Vector3i(11, 0, 12), Vector3i(20, 0, 20)])
	var trap = Trap.new()
	trap.position = dm.tile_to_world(trapped)
	dm.add_child(trap)
	var pair := await _arrive(dm, Vector3i(20, 0, 20), at)
	_check(pair[0].tile == at, "the newcomer takes the tile")
	_check(
		pair[1].tile == Vector3i(11, 0, 12) and dm.occupant_at(pair[1].tile) == pair[1],
		"the group there moves to the ORDINARY tile, not the trap (%s)" % pair[1].tile
	)
	await _drop_field(dm)


func _check_push_onto_trap() -> void:
	var at := Vector3i(11, 0, 11)
	var trapped := Vector3i(12, 0, 11)
	var dm := _field([at, trapped, Vector3i(20, 0, 20)])
	var trap = Trap.new()
	trap.position = dm.tile_to_world(trapped)
	dm.add_child(trap)
	var pair := await _arrive(dm, Vector3i(20, 0, 20), at)
	_check(pair[1].tile == trapped, "no ordinary tile: pushed onto the trap")
	_check(trap.is_spent(), "and the trap goes off")
	await _drop_field(dm)


func _check_push_over_ledge() -> void:
	var at := Vector3i(11, 1, 11)
	var below := Vector3i(12, 0, 11)
	var dm := _field([at, below, Vector3i(20, 1, 20)])
	var pair := await _arrive(dm, Vector3i(20, 1, 20), at)
	_check(pair[0].tile == at, "the newcomer takes the tile on the ledge")
	_check(pair[1].tile == below, "the group there is pushed off the ledge (%s)" % pair[1].tile)
	await _drop_field(dm)


func _check_push_chain() -> void:
	var at := Vector3i(11, 0, 11)
	var mid := Vector3i(12, 0, 11)
	var end := Vector3i(13, 0, 11)
	var dm := _field([at, mid, end, Vector3i(20, 0, 20)])
	var blocker := _spawn_rival(dm, mid)
	var pair := await _arrive(dm, Vector3i(20, 0, 20), at)
	_check(pair[0].tile == at, "the newcomer takes the tile in the corridor")
	_check(pair[1].tile == mid, "the group there takes its neighbour's place")
	_check(blocker.tile == end, "which is pushed along in turn")
	_check(
		dm.occupant_at(at) == pair[0] and dm.occupant_at(mid) == pair[1],
		"occupancy follows all three"
	)
	await _drop_field(dm)
