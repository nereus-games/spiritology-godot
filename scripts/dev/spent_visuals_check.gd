## Headless check on the cross-cutting "spent mechanism" rule: anything you can no longer
## interact with must stop presenting itself as ACTIVE — a greyed 3D marker (or a removed one,
## when the mechanism leaves nothing behind), `is_spent()` true (which is what the mini-map reads
## to dim the tile), and a return to the active state when it rearms between visits.
##
## Run with: Godot --headless --path . res://scenes/dev/spent_visuals_check.tscn
## As a start scene rather than --script; see geometry_check.gd.
extends Node

const ScenarioCatalog := preload("res://scripts/dev/scenario_catalog.gd")
const EXPLORATION := preload("res://scenes/exploration/exploration.tscn")
const DungeonMechanism := preload("res://scripts/exploration/mechanisms/dungeon_mechanism.gd")

var _fails: Array[String] = []


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
	await _check_grounds()
	await _check_crystal()
	await _check_trap()
	await _check_decor()
	print("")
	if _fails.is_empty():
		print("ALL OK")
	else:
		print("FAILURES: %s" % [_fails])
	get_tree().quit(0 if _fails.is_empty() else 1)


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------


func _setup(scenario: StringName) -> Dictionary:
	ScenarioCatalog.selected_id = scenario
	var scene = EXPLORATION.instantiate()
	get_tree().root.add_child(scene)
	await get_tree().process_frame
	return {
		"scene": scene, "dm": scene.get_node("DungeonManager"), "player": scene.get_node("Player")
	}


func _teardown(ctx: Dictionary) -> void:
	ctx.scene.queue_free()
	await get_tree().process_frame


## The first mechanism on a tile exposing `prop`; each type has state of its own.
func _mech_at(dm, tile: Vector3i, prop: String) -> Node:
	for m in dm.mechanisms_at(tile):
		if prop in m:
			return m
	return null


func _is_greyed(m: Node) -> bool:
	var marker: MeshInstance3D = m._marker
	if marker == null or marker.material_override == null:
		return false
	return marker.material_override.albedo_color.is_equal_approx(DungeonMechanism.SPENT_COLOR)


func _is_active_looking(m: Node) -> bool:
	return m._marker != null and not _is_greyed(m)


# --------------------------------------------------------------------------
# Special grounds: dug crumbly ground (greyed, rearmed between visits) and recycled litter
# (marker REMOVED, since the tile has become ordinary floor)
# --------------------------------------------------------------------------


func _check_grounds() -> void:
	print("[crumbly ground dug · litter recycled]")
	var ctx := await _setup(&"grounds")
	var ground := _mech_at(ctx.dm, Vector3i(1, 0, 1), "info_chance")
	var litter := _mech_at(ctx.dm, Vector3i(1, 0, 3), "loot_max")
	_check(ground != null and litter != null, "crumbly ground and litter in place")
	_check(
		_is_active_looking(ground) and not ground.is_spent(),
		"before: the crumbly ground looks active"
	)
	ctx.player.teleport_to(Vector3i(1, 0, 1))
	ground.dig(ctx.player)
	_check(
		ground.is_spent(),
		'dug: is_spent(), so the map dims the tile — the doc\'s "an icon is shown"'
	)
	_check(_is_greyed(ground), "dug: marker greyed out")
	ground.reset_between_visits()
	_check(
		not ground.is_spent() and _is_active_looking(ground),
		"next visit: diggable again AND coloured again"
	)

	_check(_is_active_looking(litter) and not litter.is_spent(), "before: the litter looks active")
	litter.recycle(ctx.player)
	_check(litter.is_spent(), "recycled: is_spent()")
	_check(litter._marker == null, "recycled: marker REMOVED, the tile is ordinary floor")
	_check(not litter.blocks_walk(), "recycled: you walk over it, matching the visual")
	await _teardown(ctx)


# --------------------------------------------------------------------------
# Refresh crystal: greyed but NOT flattened, since it is still an obstacle
# --------------------------------------------------------------------------


func _check_crystal() -> void:
	print("[refresh crystal used]")
	var ctx := await _setup(&"chests")
	var crystal := _mech_at(ctx.dm, Vector3i(0, 0, 2), "_used")
	_check(crystal != null and _is_active_looking(crystal), "before: the crystal looks active")
	crystal.refresh()
	_check(crystal.is_spent(), "used: is_spent()")
	_check(_is_greyed(crystal), "used: marker greyed out")
	_check(
		is_equal_approx(crystal._marker.scale.y, 1.0),
		"used: NOT flattened, since it is still an impassable obstacle"
	)
	_check(crystal.blocks_walk(), "used: still blocks the passage")
	crystal.reset_between_visits()
	_check(not crystal.is_spent() and _is_active_looking(crystal), "next visit: crystal rearmed")
	await _teardown(ctx)


# --------------------------------------------------------------------------
# Trap: already conformant before this pass — this locks the behaviour in
# --------------------------------------------------------------------------


func _check_trap() -> void:
	print("[trap sprung]")
	var ctx := await _setup(&"traps")
	var trap := _mech_at(ctx.dm, Vector3i(1, 0, 2), "kind")
	_check(trap != null and not trap.is_spent(), "before: trap armed")
	trap.reactivates = true
	trap.on_enter(ctx.player)
	_check(trap.is_spent(), "sprung: is_spent()")
	_check(_is_greyed(trap), "sprung: marker greyed out")
	trap.reset_between_visits()
	_check(
		not trap.is_spent() and _is_active_looking(trap),
		"rearming version: armed again AND coloured again"
	)
	await _teardown(ctx)


# --------------------------------------------------------------------------
# Examinable decor: greyed, not flattened, since it is a wall element
# --------------------------------------------------------------------------


func _check_decor() -> void:
	print("[decor examined]")
	var ctx := await _setup(&"walls")
	var decor := _mech_at(ctx.dm, Vector3i(0, 0, 1), "decor_type")
	_check(decor != null and _is_active_looking(decor), "before: the decor looks active")
	decor.examine(ctx.player)
	_check(decor.is_spent(), "examined: is_spent()")
	_check(_is_greyed(decor), "examined: marker greyed out")
	_check(is_equal_approx(decor._marker.scale.y, 1.0), "examined: NOT flattened, a wall element")
	await _teardown(ctx)
