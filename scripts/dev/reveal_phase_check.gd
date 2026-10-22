## Headless check on the REVEAL phase of the exploration turn (player, then reveal of
## mechanisms, then rivals, then activation) and on the first clause of Reveal Traps: "When
## entering a dungeon level, reveals the position of the 3 closest traps".
##
## Runs on the "traps" scenario: three traps already known along the corridor, one hidden at its
## far end, to which this check adds another.
##
## Run with: Godot --headless --path . res://scenes/dev/reveal_phase_check.tscn
## As a start scene rather than --script; see geometry_check.gd.
extends Node

const ScenarioCatalog := preload("res://scripts/dev/scenario_catalog.gd")
const EXPLORATION := preload("res://scenes/exploration/exploration.tscn")
const Trap := preload("res://scripts/exploration/mechanisms/trap.gd")

## A teammate species WITHOUT the reveal_traps talent, and one WITH it.
const NO_TALENT_TEAMMATE := &"erzelak"
const REVEAL_TRAPS_TEAMMATE := &"razel"

var _fails: Array[String] = []

## How many traps were already revealed each time the stand-in rival played.
var _seen_by_rival: Array = []


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
	await _check_entry_without_talent()
	await _check_entry_with_talent()
	await _check_reveal_phase()
	print("")
	if _fails.is_empty():
		print("ALL OK")
	else:
		print("FAILURES: %s" % [_fails])
	get_tree().quit(0 if _fails.is_empty() else 1)


## Builds the "traps" scenario with the given teammate and returns {scene, dm, player}.
func _setup(teammate: StringName) -> Dictionary:
	ScenarioCatalog.selected_id = &"traps"
	ScenarioCatalog.teammate_species = teammate
	var scene = EXPLORATION.instantiate()
	get_tree().root.add_child(scene)
	await get_tree().process_frame
	return {
		"scene": scene, "dm": scene.get_node("DungeonManager"), "player": scene.get_node("Player")
	}


func _teardown(ctx: Dictionary) -> void:
	ctx.scene.queue_free()
	await get_tree().process_frame


func _trap_at(dm, tile: Vector3i):
	for m in dm.mechanisms_at(tile):
		if m.is_floor_trap():
			return m
	return null


# --------------------------------------------------------------------------
# Entering a level
# --------------------------------------------------------------------------


func _check_entry_without_talent() -> void:
	print("[entering a level without Reveal Traps]")
	var ctx := await _setup(NO_TALENT_TEAMMATE)
	var hidden = _trap_at(ctx.dm, Vector3i(1, 0, 8))
	_check(hidden != null and not hidden.revealed, "the far trap stays hidden")
	await _teardown(ctx)


func _check_entry_with_talent() -> void:
	print("[entering a level with Reveal Traps]")
	var ctx := await _setup(REVEAL_TRAPS_TEAMMATE)
	var hidden = _trap_at(ctx.dm, Vector3i(1, 0, 8))
	_check(hidden != null and hidden.revealed, "the hidden trap is revealed on entry")
	_check(hidden != null and hidden.is_active(), "revealed is not sprung: the trap is armed")
	await _teardown(ctx)


# --------------------------------------------------------------------------
# The phase itself
# --------------------------------------------------------------------------


func _check_reveal_phase() -> void:
	print("[the reveal phase of the turn]")
	var ctx := await _setup(NO_TALENT_TEAMMATE)
	var dm = ctx.dm
	# Make every trap unknown, and add a fifth, so that "the 3 closest" means something.
	ScenarioCatalog._place(dm, Trap, Vector3i(1, 0, 7), {"kind": Trap.Kind.TELEPORT})
	var traps: Array = []
	for z in [2, 4, 6, 7, 8]:
		var t = _trap_at(dm, Vector3i(1, 0, z))
		t.revealed = false
		traps.append(t)
	# A stand-in rival that notes what was revealed when its turn comes.
	var spy := Node3D.new()
	spy.set_script(_spy_script())
	spy.owner_check = self
	spy.traps = traps
	dm.add_child(spy)
	dm.register_rival(spy)

	dm.advance_turn()
	_check(not _any_revealed(traps), "a turn nobody asked a reveal of reveals nothing")

	dm.request_trap_reveal(3, Vector3i(1, 0, 0))
	_check(not _any_revealed(traps), "a request waits for the phase")
	dm.advance_turn()
	_check(
		traps[0].revealed and traps[1].revealed and traps[2].revealed,
		"the 3 closest traps are revealed by the turn"
	)
	_check(not traps[3].revealed and not traps[4].revealed, "the farther ones are not")
	_check(traps[0].is_active(), "revealed but not disarmed")
	_check(
		_seen_by_rival.size() == 2 and _seen_by_rival[1] == 3,
		"the reveal came BEFORE the rivals played (%s)" % [_seen_by_rival]
	)

	dm.request_trap_reveal(3, Vector3i(1, 0, 0))
	dm.advance_turn()
	_check(traps[3].revealed and traps[4].revealed, "a later request takes the unknown ones left")
	_check(dm.run_reveal_phase().is_empty(), "a request is resolved once, not every turn")
	await _teardown(ctx)


func _any_revealed(traps: Array) -> bool:
	for t in traps:
		if t.revealed:
			return true
	return false


## A rival-shaped node that records how many traps were already revealed when it played.
func _spy_script() -> GDScript:
	var s := GDScript.new()
	s.source_code = """extends Node3D
var owner_check
var traps: Array = []
func take_turn(_player_tile) -> void:
	var n := 0
	for t in traps:
		if t.revealed:
			n += 1
	owner_check._seen_by_rival.append(n)
"""
	s.reload()
	return s
