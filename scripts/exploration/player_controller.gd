## Player movement on the dungeon grid: 3D, first person.
##
## Orthogonal cell-by-cell movement relative to facing, with smoothed transitions and 90-degree
## turns. Asks the [DungeonManager] (the "dungeon" group) about walkability and occupancy, and
## starts an encounter on entering a rival's cell. A successful step advances the turn, through
## [method DungeonManager.advance_turn].
class_name PlayerController
extends Node3D

const AfflictionState := preload("res://scripts/exploration/mechanisms/affliction_state.gd")

@export var move_duration := 0.18
## How fast the body catches up to the target angle, in degrees per second. High values keep
## free look glued to the mouse while 90-degree turns stay smooth. Ported from the prototype.
@export var yaw_follow_speed := 720.0

var cell: Vector3i
var _dungeon: DungeonManager
var _busy := false
## The target VISUAL yaw in degrees — the rigid base plus free look. The body catches up to
## it.
var _target_yaw_deg := 0.0
## The MOVEMENT yaw in degrees, always a multiple of 90. Decoupled from the visual one, which
## is what guarantees orthogonal steps: never a diagonal, even while looking at 45 degrees. A
## facing only counts for movement once the 90-degree turn has completed.
var _move_yaw_deg := 0.0

## Movement lock: while set, move and turn input is ignored. Used by the narrow-bridge balance
## test, which drives the position directly.
var input_locked := false

## Lingering effects on the player (poison, disarray). Read by the traps through the
## `affliction` property, by duck typing.
var affliction := AfflictionState.new()

## Invisibility (fog mantel): how many more cells the rivals cannot see the player for. Cleared
## by an encounter OR by springing a trap.
var invisible_moves := 0
## Not-chased (torment veil, a costume): how many more cells the rivals will not give chase
## for. Cleared by an encounter, but NOT by a trap.
var unpursued_moves := 0
## The species the player looks like, when wearing a costume.
var disguise_species := &""


func _ready() -> void:
	_dungeon = get_tree().get_first_node_in_group("dungeon") as DungeonManager
	if _dungeon == null:
		push_error("[PlayerController] no DungeonManager in the 'dungeon' group.")
		return
	cell = _dungeon.world_to_cell(global_position)
	global_position = _dungeon.cell_to_world(cell)
	_dungeon.register_player(self)
	add_to_group("player")  # how the HUD finds us, for the contextual actions

	# Yaw is driven by PlayerInputHandler — a rigid base plus mouse free look, as in the
	# prototype — and the body continuously catches up to the target angle in _process.
	_target_yaw_deg = rad_to_deg(rotation.y)


## Whether no move or turn is under way, and so a new action is allowed.
func is_at_rest() -> bool:
	return not _busy


## The direction currently faced, as a cell delta (x, 0, z), for querying the contextual actions
## of the cell being looked at. Based on the cardinal MOVEMENT facing rather than on free look:
## you interact with the cell squarely in front of you.
func facing_delta() -> Vector3i:
	var world := Basis(Vector3.UP, deg_to_rad(_move_yaw_deg)) * Vector3.FORWARD
	return Vector3i(roundi(world.x), 0, roundi(world.z))


func _process(delta: float) -> void:
	# The body continuously catches up to the target angle — free look plus 90-degree turns — by
	# the shortest way round.
	var target := deg_to_rad(_target_yaw_deg)
	var step := deg_to_rad(yaw_follow_speed) * delta
	rotation.y += clampf(angle_difference(rotation.y, target), -step, step)


## Sets the target VISUAL yaw in degrees. Written by [PlayerInputHandler].
func set_yaw_target(deg: float) -> void:
	_target_yaw_deg = deg


## Sets the MOVEMENT yaw in degrees, a multiple of 90. Written by [PlayerInputHandler] once a
## 90-degree turn has completed.
func set_move_yaw(deg: float) -> void:
	_move_yaw_deg = deg


## The current target yaw in degrees. Read by [PlayerInputHandler] to initialise itself.
func current_yaw_deg() -> float:
	return _target_yaw_deg


## Turns the player at once — body, visual target and movement facing — when placing them.
func set_start_yaw(rad: float) -> void:
	rotation.y = rad
	_target_yaw_deg = rad_to_deg(rad)
	_move_yaw_deg = rad_to_deg(rad)


## A turn has just completed, from the keyboard or from free look drifting past
## [member PlayerInputHandler.commit_angle]. It advances the turn, like a step.
func rotated_90() -> void:
	if _dungeon != null:
		_dungeon.advance_turn()


## Attempts a step in a LOCAL direction (Vector3.FORWARD/BACK/LEFT/RIGHT).
func try_move(local_dir: Vector3) -> void:
	if _busy or _dungeon == null or input_locked:
		return
	# Disarray: a share of moves is deflected into a DIFFERENT translation, per the design doc.
	if affliction.consume_move():
		local_dir = _random_translation_except(local_dir)
	# Direction taken from the cardinal MOVEMENT facing, which guarantees an orthogonal step and
	# never a diagonal, even while looking at 45 degrees.
	var world := Basis(Vector3.UP, deg_to_rad(_move_yaw_deg)) * local_dir
	var delta := Vector3i(roundi(world.x), 0, roundi(world.z))
	if delta == Vector3i.ZERO:
		return
	var target := cell + delta

	# A closed gateway on the edge being crossed: nothing gets through — no stairs, no fall, no
	# encounter.
	if _dungeon.is_edge_blocked(cell, target):
		return

	# Stairs ahead, as in the prototype: you are carried two cells further plus a floor change.
	# They can ONLY be taken along their own axis (`face_dir`); side-on they block like a wall.
	var stairs := _stairs_at(target)
	if stairs != null:
		if delta == stairs.face_dir:
			var dest: Vector3i = stairs.stairs_destination(cell, delta)
			if _dungeon.is_floor(dest):
				await _climb_step(dest)
		return  # wrong direction: blocked

	if _dungeon.is_blocked_by_mechanism(target):
		return  # an impassable mechanism, such as a closed gateway
	if not _dungeon.is_floor(target):
		# No floor here: a fall if there is floor further down (the lip of a drop), a wall if
		# not.
		var landing := _dungeon.fall_landing(target)
		if landing == target:
			# Nothing below means a wall — unless level design left an outright hole, in which
			# case the fall is bottomless, and fatal.
			if _dungeon.is_bottomless(target):
				await fall_forever(target)
			return
		await fall_to(landing, target.y - landing.y)
		return
	var occ := _dungeon.occupant_at(target)
	if occ != null:
		_dungeon.request_encounter(occ, false)  # an encounter, with no move
		return

	cell = target
	_busy = true
	var tween := create_tween()
	tween.tween_property(self, "global_position", _dungeon.cell_to_world(target), move_duration)
	await tween.finished
	_busy = false
	# A step eats into the stealth states: invisibility and not-chased.
	_tick_hidden_on_move()
	# The reached cell's mechanisms first, such as traps, then the turn advances.
	_dungeon.notify_entered(cell, self)
	_dungeon.advance_turn()


## A fall to `landing`, the floor cell below: an animated descent, damage scaling with the
## number of levels, then the usual resolution — the cell's mechanisms, then the turn.
##
## Public because the narrow-bridge driver ([code]exploration.gd[/code]) uses it to make a fall
## off a bridge exactly an ordinary fall: same depth, same damage, same turn.
func fall_to(landing: Vector3i, levels: int) -> void:
	_dungeon.notify_level_change(self, cell, landing)  # watching rivals can follow
	cell = landing
	_busy = true
	var tween := create_tween()
	tween.tween_property(self, "global_position", _dungeon.cell_to_world(landing), 0.35)
	await tween.finished
	_busy = false
	var dmg := DungeonManager.fall_damage(levels)
	GameSession.apply_den_damage(GameSession.PartySlot.MAIN, dmg)
	GameSession.apply_den_damage(GameSession.PartySlot.TEAMMATE, dmg)
	GameSession.resolve_party_wipe()
	_tick_hidden_on_move()
	_dungeon.notify_entered(cell, self)
	_dungeon.advance_turn()


## A BOTTOMLESS fall, into an outright hole left by level design: the duo falls out of the
## dungeon and is devitalised — a floor you never reach is a floor too far down to survive. The
## step is not silently blocked: the dungeon is at fault, and that should be visible in play.
##
## ## TODO(dungeon checker): a bottomless hole is always an authoring mistake. It should be
## caught when the dungeon loads rather than by falling into it, once a dungeon validator
## exists.
func fall_forever(into: Vector3i) -> void:
	input_locked = true
	_busy = true
	push_warning(
		"[PlayerController] bottomless fall at %s: level design left a hole with no floor." % into
	)
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(
		self, "global_position", _dungeon.cell_to_world(into) - Vector3(0.0, 6.0, 0.0), 0.8
	)
	await tween.finished
	_busy = false
	GameSession.set_den(GameSession.PartySlot.MAIN, 0)
	GameSession.set_den(GameSession.PartySlot.TEAMMATE, 0)
	GameSession.resolve_party_wipe()  # devitalised, so out of the dungeon
	input_locked = false


## A random local translation direction other than `dir` — the disarray deflection.
func _random_translation_except(dir: Vector3) -> Vector3:
	var dirs := [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]
	dirs.erase(dir)
	return dirs[randi() % dirs.size()]


## Instant relocation onto a cell (the teleport trap). Occupancy is handled by
## [method DungeonManager.teleport_actor] — and the player occupies no cell anyway.
func teleport_to(to_cell: Vector3i) -> void:
	cell = to_cell
	global_position = _dungeon.cell_to_world(to_cell)


## The staircase on cell `c`, recognised by exposing `stairs_destination`, or null.
func _stairs_at(c: Vector3i) -> Node:
	for m in _dungeon.mechanisms_at(c):
		if m.has_method("stairs_destination"):
			return m
	return null


## Takes a staircase: a SMOOTH climb or descent to `dest`, another floor two cells away, then
## the usual resolution — the cell's mechanisms, then the turn.
func _climb_step(dest: Vector3i) -> void:
	if dest.y != cell.y:
		_dungeon.notify_level_change(self, cell, dest)  # watching rivals can follow
	cell = dest
	_busy = true
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "global_position", _dungeon.cell_to_world(dest), 0.4)
	await tween.finished
	_busy = false
	_tick_hidden_on_move()
	_dungeon.notify_entered(cell, self)
	_dungeon.advance_turn()


# --------------------------------------------------------------------------
# Stealth (invisibility, not-chased) — exploration abilities and objects
# --------------------------------------------------------------------------


## Hides the player from the rivals for `tiles` moves (fog mantel). Takes the larger value.
func set_invisible(tiles: int) -> void:
	invisible_moves = maxi(invisible_moves, tiles)


## Stops the rivals giving chase for `moves` moves (torment veil, a costume).
func set_unpursued(moves: int, species: StringName = &"") -> void:
	unpursued_moves = maxi(unpursued_moves, moves)
	if species != &"":
		disguise_species = species


func is_hidden_from_rivals() -> bool:
	return invisible_moves > 0 or unpursued_moves > 0


## Clears invisibility only — the fog mantel rule, where a trap or an encounter breaks it.
func clear_invisibility() -> void:
	invisible_moves = 0


## Clears all stealth, on entering an encounter.
func clear_hidden() -> void:
	invisible_moves = 0
	unpursued_moves = 0
	disguise_species = &""


## Counts the stealth states down by one move.
func _tick_hidden_on_move() -> void:
	if invisible_moves > 0:
		invisible_moves -= 1
	if unpursued_moves > 0:
		unpursued_moves -= 1
		if unpursued_moves == 0:
			disguise_species = &""


## End of turn: applies the lingering afflictions. Poison takes DEN off BOTH characters, since
## the player on the map is the whole duo, and triggers leaving the dungeon if the duo is
## entirely devitalised.
func on_turn_elapsed() -> void:
	var dmg := affliction.tick_poison()
	if dmg > 0:
		GameSession.apply_den_damage(GameSession.PartySlot.MAIN, dmg)
		GameSession.apply_den_damage(GameSession.PartySlot.TEAMMATE, dmg)
		GameSession.resolve_party_wipe()
