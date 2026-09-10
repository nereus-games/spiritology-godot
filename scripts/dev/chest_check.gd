## Headless check on chests against the design doc ("Mechanisms / Chest", plus the chest clauses
## of the Reveal Traps and Trick to Reveal talents). Exercises the loot, the disguised trap, the
## choice Reveal Traps offers, and the fact that a rival does not consume a loot chest — all in
## the real "chests" scenario.
##
## Run with: Godot --headless --path . res://scenes/dev/chest_check.tscn
## As a start scene rather than --script; see geometry_check.gd.
extends Node

const ScenarioCatalog := preload("res://scripts/dev/scenario_catalog.gd")
const EXPLORATION := preload("res://scenes/exploration/exploration.tscn")
const RIVAL_SCENE := preload("res://scenes/exploration/rival/rival.tscn")
const DungeonMechanism := preload("res://scripts/exploration/mechanisms/dungeon_mechanism.gd")

## Tiles of the two chests in the "chests" scenario.
const LOOT_TILE := Vector3i(1, 0, 1)
const TRAP_TILE := Vector3i(1, 0, 3)

## A teammate species WITHOUT the reveal_traps talent (érzélak carries trick_to_reveal).
const NO_TALENT_TEAMMATE := &"erzelak"
## A teammate species WITH the reveal_traps talent.
const REVEAL_TRAPS_TEAMMATE := &"razel"

var _fails: Array[String] = []
var _messages: Array[String] = []


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
	await _check_loot_chest()
	await _check_rival_on_loot_chest()
	await _check_trap_chest()
	await _check_reveal_traps_declined()
	await _check_reveal_traps_accepted()
	print("")
	if _fails.is_empty():
		print("ALL OK")
	else:
		print("FAILURES: %s" % [_fails])
	get_tree().quit(0 if _fails.is_empty() else 1)


# --------------------------------------------------------------------------
# The test field
# --------------------------------------------------------------------------


## Builds the "chests" scenario and returns {scene, dm, player, loot, trap}. `teammate` sets the
## duo's talent, since the chest reads GameSession when it opens.
func _setup(teammate: StringName) -> Dictionary:
	ScenarioCatalog.selected_id = &"chests"
	var scene = EXPLORATION.instantiate()
	get_tree().root.add_child(scene)
	await get_tree().process_frame
	var dm = scene.get_node("DungeonManager")
	var player = scene.get_node("Player")
	GameSession.teammate = teammate
	GameSession.inventory.clear()
	_messages.clear()
	dm.message_posted.connect(func(text: String) -> void: _messages.append(text))
	return {
		"scene": scene,
		"dm": dm,
		"player": player,
		"loot": _chest_at(dm, LOOT_TILE),
		"trap": _chest_at(dm, TRAP_TILE),
	}


func _teardown(ctx: Dictionary) -> void:
	ctx.scene.queue_free()
	await get_tree().process_frame


## The chest on a tile, or null.
func _chest_at(dm, tile: Vector3i) -> Node:
	for m in dm.mechanisms_at(tile):
		if "is_trap" in m:
			return m
	return null


func _inventory_total() -> int:
	var total := 0
	for count in GameSession.inventory.values():
		total += count
	return total


## Whether the mechanism's marker is greyed out, meaning spent.
func _is_greyed(mechanism: Node) -> bool:
	var marker: MeshInstance3D = mechanism._marker
	if marker == null or marker.material_override == null:
		return false
	return marker.material_override.albedo_color.is_equal_approx(DungeonMechanism.SPENT_COLOR)


func _action_ids(dm, tile: Vector3i, who: Node) -> Array:
	var ids := []
	for a in dm.actions_for(tile, Vector3i(0, 0, 1), who):
		ids.append(a.id)
	return ids


# --------------------------------------------------------------------------
# Loot chest ("will give objects if the player steps on them")
# --------------------------------------------------------------------------


func _check_loot_chest() -> void:
	print("[loot chest]")
	var ctx := await _setup(REVEAL_TRAPS_TEAMMATE)
	var chest = ctx.loot
	_check(chest != null and not chest.is_trap, "a loot chest on %s" % LOOT_TILE)
	_check(
		not chest.is_opened() and not chest.revealed, "to start with: neither opened nor revealed"
	)
	chest.reveal()
	_check(
		chest.revealed and not chest.is_opened(),
		"reveal() reveals without opening (the Trick to Reveal talent)"
	)
	ctx.player.teleport_to(LOOT_TILE)
	chest.on_enter(ctx.player)
	var got := _inventory_total()
	_check(chest.is_opened(), "stepping on it opens it")
	_check(
		got >= chest.loot_min and got <= chest.loot_max,
		"loot within [%d, %d] (got %d)" % [chest.loot_min, chest.loot_max, got]
	)
	_check(_messages.size() == 1, 'the loot is announced: "%s"' % ["".join(_messages)])
	_check(_is_greyed(chest), "an emptied chest is greyed out: no longer actionable, so not active")
	chest.on_enter(ctx.player)
	_check(_inventory_total() == got, "a chest does not reopen; it opens once only")
	await _teardown(ctx)


# --------------------------------------------------------------------------
# A rival walking over a loot chest does not consume it: it has no inventory
# --------------------------------------------------------------------------


func _check_rival_on_loot_chest() -> void:
	print("[rival on a loot chest]")
	var ctx := await _setup(REVEAL_TRAPS_TEAMMATE)
	var chest = ctx.loot
	var rival = RIVAL_SCENE.instantiate()
	rival.species_id = &"kalilk"
	rival.position = ctx.dm.tile_to_world(LOOT_TILE)
	ctx.dm.add_child(rival)
	await get_tree().process_frame
	chest.on_enter(rival)
	_check(not chest.is_opened(), "the chest stays closed")
	_check(_inventory_total() == 0, "nothing added to the player's inventory")
	ctx.player.teleport_to(LOOT_TILE)
	chest.on_enter(ctx.player)
	_check(
		chest.is_opened() and _inventory_total() > 0, "the loot was indeed waiting for the player"
	)
	await _teardown(ctx)


# --------------------------------------------------------------------------
# Trapped chest without the talent ("some are actually teleportation traps in disguise")
# --------------------------------------------------------------------------


func _check_trap_chest() -> void:
	print("[trapped chest, duo without Reveal Traps]")
	var ctx := await _setup(NO_TALENT_TEAMMATE)
	var chest = ctx.trap
	_check(chest != null and chest.is_trap, "a trapped chest on %s" % TRAP_TILE)
	ctx.player.teleport_to(TRAP_TILE)
	ctx.player.set_invisible(5)  # fog mantel running: the trap has to break it
	chest.on_enter(ctx.player)
	_check(not chest.is_pending(), "no choice offered without the talent")
	_check(chest.is_opened(), "the chest is consumed")
	_check(ctx.player.tile != TRAP_TILE, "the player is teleported (%s)" % [ctx.player.tile])
	_check(_inventory_total() == 0, "no loot: a pure trap")
	_check(_is_greyed(chest), "a sprung trapped chest is greyed out")
	_check(not ctx.player.is_hidden_from_rivals(), "the trap breaks invisibility (fog mantel)")
	await _teardown(ctx)


# --------------------------------------------------------------------------
# Trapped chest with Reveal Traps ("they can decide to teleport or not. The chest gives 1 or
# more object no matter what, but more if players choose to teleport.")
# --------------------------------------------------------------------------


func _check_reveal_traps_declined() -> void:
	print("[trapped chest + Reveal Traps: declined]")
	var ctx := await _setup(REVEAL_TRAPS_TEAMMATE)
	var chest = ctx.trap
	_check(GameSession.party_has_talent(&"reveal_traps"), "the duo does carry reveal_traps")
	ctx.player.teleport_to(TRAP_TILE)
	chest.on_enter(ctx.player)
	_check(chest.is_pending() and not chest.is_opened(), "the chest waits for the player's choice")
	_check(ctx.player.tile == TRAP_TILE, "nobody is teleported while nothing has been chosen")
	var ids := _action_ids(ctx.dm, TRAP_TILE, ctx.player)
	_check(
		&"chest_teleport" in ids and &"chest_decline" in ids,
		"both actions are offered (%s)" % [ids]
	)
	chest.decline_teleport(ctx.player)
	_check(chest.is_opened() and not chest.is_pending(), "the chest is consumed once chosen")
	_check(ctx.player.tile == TRAP_TILE, "declined: the player stays put")
	_check(
		_inventory_total() == chest.trap_loot_declined,
		"declined: %d object(s) anyway" % chest.trap_loot_declined
	)
	_check(
		ctx.dm.actions_for(TRAP_TILE, Vector3i(0, 0, 1), ctx.player).is_empty(),
		"no action left on the tile"
	)
	await _teardown(ctx)


func _check_reveal_traps_accepted() -> void:
	print("[trapped chest + Reveal Traps: accepted]")
	var ctx := await _setup(REVEAL_TRAPS_TEAMMATE)
	var chest = ctx.trap
	ctx.player.teleport_to(TRAP_TILE)
	chest.on_enter(ctx.player)
	chest.accept_teleport(ctx.player)
	_check(
		ctx.player.tile != TRAP_TILE, "accepted: the player is teleported (%s)" % [ctx.player.tile]
	)
	_check(
		_inventory_total() == chest.trap_loot_accepted,
		"accepted: %d objects" % chest.trap_loot_accepted
	)
	_check(
		chest.trap_loot_accepted > chest.trap_loot_declined,
		"the design doc requires more loot for accepting"
	)
	await _teardown(ctx)
