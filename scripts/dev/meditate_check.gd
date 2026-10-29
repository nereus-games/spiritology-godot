## Headless check of the Meditate exploration action: always on offer, recovers ETH for the duo,
## and when facing a meditation gateway counts towards opening it WITHOUT a second menu entry.
##
## Run with: Godot --headless --path . res://scenes/dev/meditate_check.tscn
## As a start scene rather than --script; see geometry_check.gd.
extends Node

const ScenarioCatalog := preload("res://scripts/dev/scenario_catalog.gd")
const EXPLORATION := preload("res://scenes/exploration/exploration.tscn")
const ExtraActions := preload("res://scripts/exploration/exploration_extra_actions.gd")
const ActionMenu := preload("res://scripts/ui/exploration_action_menu.gd")
const ExplorationContext :=preload("res://scripts/exploration/abilities/exploration_context.gd")

## The meditation gateway of the "gates" scenario sits on the edge south of this tile.
const GATE_TILE := Vector3i(1, 0, 9)
## Open floor of the same scenario, far from every gateway.
const PLAIN_TILE := Vector3i(1, 0, 1)
const SOUTH := Vector3i(0, 0, 1)

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
	ScenarioCatalog.selected_id = &"gates"
	var scene = EXPLORATION.instantiate()
	get_tree().root.add_child(scene)
	await get_tree().process_frame
	var dm = scene.get_node("DungeonManager")
	var player = scene.get_node("Player")
	player.set_start_yaw(PI)  # facing +z, towards the gateways
	_check(player.facing_delta() == SOUTH, "the player faces south")
	var extra = ExtraActions.new(ExplorationContext.new(dm, player))

	print("[Meditate, away from any gateway]")
	player.teleport_to(PLAIN_TILE)
	var menu: Array = _menu(extra, dm, player)
	_check(_count(menu, &"meditate") == 1, "Meditate is on offer (%s)" % [_ids(menu)])
	GameSession.set_eth(GameSession.PartySlot.MAIN, 10)
	GameSession.set_eth(GameSession.PartySlot.TEAMMATE, 20)
	var gain := BalanceData.current().meditate_eth
	_pick(menu, &"meditate")
	_check(
		GameSession.get_eth(GameSession.PartySlot.MAIN) == 10 + gain,
		"the main character recovers %d ETH" % gain
	)
	_check(
		GameSession.get_eth(GameSession.PartySlot.TEAMMATE) == 20 + gain,
		"the teammate recovers %d ETH" % gain
	)
	GameSession.set_eth(GameSession.PartySlot.MAIN, GameSession.MAX_ETH - 1)
	_pick(_menu(extra, dm, player), &"meditate")
	_check(
		GameSession.get_eth(GameSession.PartySlot.MAIN) == GameSession.MAX_ETH,
		"recovery stops at the maximum"
	)

	print("[Meditate, facing a meditation gateway]")
	player.teleport_to(GATE_TILE)
	var gate = dm.edge_mechanisms_between(GATE_TILE, GATE_TILE + SOUTH)[0]
	menu = _menu(extra, dm, player)
	_check(_count(menu, &"meditate") == 1, "a single Meditate entry (%s)" % [_ids(menu)])
	GameSession.set_eth(GameSession.PartySlot.MAIN, 0)
	for i in gate.meditations_required:
		_check(not gate.is_open(), "closed before meditation %d" % (i + 1))
		_pick(_menu(extra, dm, player), &"meditate")
	_check(gate.is_open(), "%d meditations open the gateway" % gate.meditations_required)
	_check(
		GameSession.get_eth(GameSession.PartySlot.MAIN) == gain * gate.meditations_required,
		"each meditation also recovered ETH"
	)
	_check(
		_count(_menu(extra, dm, player), &"meditate") == 1,
		"Meditate stays on offer once the gateway is open"
	)

	# TODO: this section has not been run yet (written without a Godot binary). Run the check, and
	# break set_actions on purpose to see it go red, then drop this note.
	print("[Meditate through the menu, which the HUD refreshes while the ids stay the same]")
	var gate_menu := ActionMenu.new()
	scene.add_child(gate_menu)
	await get_tree().process_frame
	var fresh_gate = dm.edge_mechanisms_between(GATE_TILE, GATE_TILE + SOUTH)[0]
	fresh_gate._open = false  # shut again: the section above opened it
	fresh_gate._meditations = 0
	player.teleport_to(PLAIN_TILE)
	gate_menu.set_actions(_menu(extra, dm, player))  # no gateway in front yet
	player.teleport_to(GATE_TILE)
	gate_menu.set_actions(_menu(extra, dm, player))  # same ids, now bound to the gateway
	gate_menu.confirm()
	_check(
		not fresh_gate.is_open() and fresh_gate._meditations == 1,
		"the menu's Meditate counts towards the gateway after walking up to it"
	)

	print("")
	if _fails.is_empty():
		print("ALL OK")
	else:
		print("FAILURES: %s" % [_fails])
	scene.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if _fails.is_empty() else 1)


## The menu as the HUD builds it.
func _menu(extra, dm, player) -> Array:
	return extra.combine(dm.actions_for(player.tile, player.facing_delta(), player))


func _pick(menu: Array, id: StringName) -> void:
	for a in menu:
		if a.id == id:
			a.callable.call()
			return


func _ids(menu: Array) -> Array:
	var ids := []
	for a in menu:
		ids.append(a.id)
	return ids


func _count(menu: Array, id: StringName) -> int:
	var n := 0
	for a in menu:
		if a.id == id:
			n += 1
	return n
