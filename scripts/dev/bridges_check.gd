## Headless check on the two bridges between exploration and the rest of the game:
##
## - Trick to Reveal: an encounter that ends on an effective dialogue reveals the closest hidden
##   chest or trap on the map it was entered from, through the one handle the encounter is given
##   ([member EncounterManager.map_reveal]);
## - Static Camouflage: 2 to 4 rival groups shown one at a time, and the choice to take one on or
##   to keep waiting ([Scouting]).
##
## Each rule has something it must touch and something it must leave alone.
##
## Run with: Godot --headless --path . res://scenes/dev/bridges_check.tscn
## As a start scene rather than --script; see geometry_check.gd.
extends Node

const ScenarioCatalog := preload("res://scripts/dev/scenario_catalog.gd")
const EXPLORATION := preload("res://scenes/exploration/exploration.tscn")
const RIVAL_SCENE := preload("res://scenes/exploration/rival/rival.tscn")
const RivalMember := preload("res://scripts/exploration/rival_member.gd")
const Trap := preload("res://scripts/exploration/mechanisms/trap.gd")
const StaticCamouflage := preload("res://scripts/exploration/abilities/impl/static_camouflage.gd")
const ExplorationContext := preload("res://scripts/exploration/abilities/exploration_context.gd")

## Tiles of the two chests in the "chests" scenario, and of a trap this check adds.
const LOOT_TILE := Vector3i(1, 0, 1)
const TRAP_CHEST_TILE := Vector3i(1, 0, 3)
const TRAP_TILE := Vector3i(1, 0, 7)

var _fails: Array[String] = []
var _messages: Array[String] = []
var _requested: Array = []


## Plays queued actions, then passes.
class Player:
	extends EncounterAgent
	var queued: Array = []
	var spy: Callable = Callable()

	func decide(individual: EncounterIndividual, manager: EncounterManager) -> EncounterAction:
		if spy.is_valid():
			spy.call(individual, manager)
		if not queued.is_empty():
			return queued.pop_front()
		return EncounterAction.of_kind(EncounterAction.Kind.PASS, [individual])


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
	await _check_nearest_hidden()
	await _check_talent_in_encounter()
	await _check_handle_reaches_manager()
	await _check_scouting_draw()
	await _check_scouting_choice()
	await _check_scouting_edges()
	await _check_scouting_surfaces()
	print("")
	if _fails.is_empty():
		print("ALL OK")
	else:
		print("FAILURES: %s" % [_fails])
	get_tree().quit(0 if _fails.is_empty() else 1)


# --------------------------------------------------------------------------
# Scaffolding
# --------------------------------------------------------------------------


func _setup() -> Dictionary:
	ScenarioCatalog.selected_id = &"chests"
	var scene = EXPLORATION.instantiate()
	get_tree().root.add_child(scene)
	await get_tree().process_frame
	var dm = scene.get_node("DungeonManager")
	_messages.clear()
	_requested.clear()
	dm.message_posted.connect(func(text: String) -> void: _messages.append(text))
	dm.encounter_requested.connect(func(r, _by: bool) -> void: _requested.append(r))
	return {"scene": scene, "dm": dm, "player": scene.get_node("Player")}


func _teardown(ctx: Dictionary) -> void:
	ctx.scene.queue_free()
	await get_tree().process_frame


func _chest_at(dm, tile: Vector3i) -> Node:
	for m in dm.mechanisms_at(tile):
		if "is_trap" in m:
			return m
	return null


func _trap_at(dm, tile: Vector3i) -> Node:
	for m in dm.mechanisms_at(tile):
		if m.is_floor_trap():
			return m
	return null


## A rival group on a tile, made of the given species (one member each).
func _group(dm, tile: Vector3i, species: Array) -> Node:
	var g = RIVAL_SCENE.instantiate()
	var members: Array = []
	for id in species:
		members.append(RivalMember.new(id, 40, 20))
	g.members = members
	g.position = dm.tile_to_world(tile)
	dm.add_child(g)
	return g


## `count` single-member groups along x = 2, clear of the corridor's mechanisms.
func _groups(dm, count: int) -> Array:
	var out: Array = []
	for i in count:
		out.append(_group(dm, Vector3i(2, 0, 1 + i), [&"kalilk"]))
	return out


# --------------------------------------------------------------------------
# Trick to Reveal
# --------------------------------------------------------------------------


func _check_nearest_hidden() -> void:
	print("[the closest hidden chest or trap]")
	var ctx := await _setup()
	var dm = ctx.dm
	ScenarioCatalog._place(dm, Trap, TRAP_TILE, {"kind": Trap.Kind.TELEPORT})
	var loot = _chest_at(dm, LOOT_TILE)
	var trap_chest = _chest_at(dm, TRAP_CHEST_TILE)
	var trap = _trap_at(dm, TRAP_TILE)
	trap.revealed = false
	_check(
		not loot.revealed and not trap_chest.revealed and not trap.revealed,
		"everything starts hidden"
	)

	var first = dm.reveal_nearest_hidden(Vector3i(1, 0, 0))
	_check(first == loot and loot.revealed, "the closest one is revealed: the loot chest")
	_check(not trap_chest.revealed and not trap.revealed, "and only that one")
	_check(loot.shows_on_map(), "a revealed chest shows on the map")
	_check(
		not _messages.is_empty() and _messages[-1] == tr("UI_CHEST_REVEALED"),
		"the player is told a chest was revealed"
	)

	var second = dm.reveal_nearest_hidden(Vector3i(1, 0, 0))
	_check(second == trap_chest, "the next call skips what is already revealed")
	var third = dm.reveal_nearest_hidden(Vector3i(1, 0, 0))
	_check(third == trap and trap.revealed, "a floor trap counts as well")
	_check(trap.is_active(), "revealing a trap does not spring it")
	_check(_messages[-1] == tr("UI_TRAP_REVEALED"), "the player is told a trap was revealed")
	_check(dm.reveal_nearest_hidden(Vector3i(1, 0, 0)) == null, "nothing hidden: nothing found")

	# Distance decides, not the order the mechanisms were placed in.
	loot.revealed = false
	trap_chest.revealed = false
	trap.revealed = false
	_check(
		dm.reveal_nearest_hidden(Vector3i(1, 0, 8)) == trap, "from the far end, the trap is closest"
	)
	_check(not loot.revealed and not trap_chest.revealed, "the others stay hidden")

	# An opened chest has nothing left to find, even if it was never marked revealed.
	trap.revealed = false
	loot._close()
	loot.revealed = false
	_check(dm.reveal_nearest_hidden(Vector3i(1, 0, 0)) == trap_chest, "an opened chest is skipped")
	await _teardown(ctx)


## A real encounter on a real manager: players erzelak (Trick to Reveal) and kalilk against a
## ravbak whose talker_chance this check sets, so that a Talk is effective or not at will.
func _encounter(chance: float) -> EncounterManager:
	var all: Array = []
	for id in [&"erzelak", &"kalilk"]:
		all.append(EncounterManager.make_individual(id, true))
	all.append(EncounterManager.make_individual(&"ravbak", false))
	all[2].species = all[2].species.duplicate()
	all[2].species.talker_chance = chance
	var m := EncounterManager.new()
	m.setup([all[0], all[1]], [all[2]], 20261022)
	m.timeline.order = all
	for f in all:
		m.set_agent(f, Player.new())
	return m


func _talk(target: EncounterIndividual) -> EncounterAction:
	return EncounterAction.of_kind(EncounterAction.Kind.TALK, [target])


func _reveal_line(m: EncounterManager) -> bool:
	for line in m.encounter_log:
		if "revealed" in line or "révélé" in line:
			return true
	return false


func _counting(m: EncounterManager, asked: Array, found := true) -> void:
	asked[0] = 0
	m.map_reveal = func() -> bool:
		asked[0] += 1
		return found


func _check_talent_in_encounter() -> void:
	print("[Trick to Reveal in an encounter]")
	var asked := [0]

	# An effective dialogue: the map is asked once.
	var m := _encounter(1.0)
	_counting(m, asked)
	(m.agent_for(m.players[0]) as Player).queued = [_talk(m.rivals[0])]
	await m.run(1)
	_check(m.last_talk_effective, "the Talk was effective")
	_check(asked[0] == 1, "an effective dialogue reveals once (%d)" % asked[0])
	_check(_reveal_line(m), "and the log says so")

	# The same talents, told the duo was defeated: an effective dialogue does not help then.
	asked[0] = 0
	for t in m._talents:
		t.on_encounter_end(m, &"defeat")
	_check(asked[0] == 0, "a defeat reveals nothing, whatever the last dialogue was")

	# An ineffective one: nothing.
	m = _encounter(0.0)
	_counting(m, asked)
	(m.agent_for(m.players[0]) as Player).queued = [_talk(m.rivals[0])]
	await m.run(1)
	_check(not m.last_talk_effective and asked[0] == 0, "an ineffective dialogue reveals nothing")

	# No dialogue at all: nothing.
	m = _encounter(1.0)
	_counting(m, asked)
	await m.run(1)
	_check(asked[0] == 0, "no dialogue, no reveal")

	# Effective first, ineffective last: it is the LAST one that counts.
	m = _encounter(1.0)
	_counting(m, asked)
	var player := m.agent_for(m.players[0]) as Player
	player.queued = [_talk(m.rivals[0]), _talk(m.rivals[0])]
	var rival: EncounterIndividual = m.rivals[0]
	player.spy = func(_f, mgr) -> void:
		if mgr.round_number == 2:
			rival.species.talker_chance = 0.0
	await m.run(2)
	_check(not m.last_talk_effective and asked[0] == 0, "only the last dialogue counts")

	# Nothing handed over, or a map with nothing hidden: no crash, and the log claims no reveal.
	m = _encounter(1.0)
	(m.agent_for(m.players[0]) as Player).queued = [_talk(m.rivals[0])]
	await m.run(1)
	_check(not _reveal_line(m), "without a map, the log claims no reveal")
	m = _encounter(1.0)
	_counting(m, asked, false)
	(m.agent_for(m.players[0]) as Player).queued = [_talk(m.rivals[0])]
	await m.run(1)
	_check(asked[0] == 1 and not _reveal_line(m), "a map with nothing hidden: no claim either")


## The handle travels from the exploration scene through TransitionManager and the encounter
## screen to the manager, and lands on the map the player stands in.
func _check_handle_reaches_manager() -> void:
	print("[the handle from the map to the manager]")
	var ctx := await _setup()
	var loot = _chest_at(ctx.dm, LOOT_TILE)
	_check(not loot.revealed, "the chest is hidden")
	var handle := Callable(ctx.scene, "_reveal_for_encounter")
	var previous := get_tree().current_scene
	TransitionManager.open_encounter([&"erzelak", &"kalilk"], [&"ravbak"], {}, [], handle)
	var screen = TransitionManager._encounter
	_check(screen != null, "the encounter opened")
	if screen != null:
		_check(screen._manager.map_reveal == handle, "the manager holds the handle it was given")
		_check(screen._manager.reveal_on_map() and loot.revealed, "using it reveals on the map")
		screen.queue_free()
		TransitionManager._encounter = null
	if previous != null:
		previous.process_mode = Node.PROCESS_MODE_INHERIT
	TransitionManager._restore_scene_hud()
	await _teardown(ctx)


# --------------------------------------------------------------------------
# Static Camouflage
# --------------------------------------------------------------------------


func _rng(seed: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	return r


func _check_scouting_draw() -> void:
	print("[the watch shows 2 to 4 groups, one at a time]")
	var ctx := await _setup()
	var dm = ctx.dm
	var groups := _groups(dm, 6)
	var totals := {}
	var in_range := true
	var all_distinct := true
	var all_on_map := true
	for seed in 40:
		dm.scouting.begin(dm.rivals(), _rng(seed), ctx.player)
		var seen: Array = []
		while dm.scouting.active:
			var g = dm.scouting.current()
			if seen.has(g):
				all_distinct = false
			if not groups.has(g):
				all_on_map = false
			seen.append(g)
			dm.scouting.wait()
		totals[seen.size()] = true
		if seen.size() < 2 or seen.size() > 4:
			in_range = false
	_check(in_range, "never fewer than 2 or more than 4 (%s)" % [totals.keys()])
	_check(totals.has(2) and totals.has(4), "both ends of the range are drawn")
	_check(all_distinct, "no group is shown twice in one watch")
	_check(all_on_map, "every group shown is one that wanders the map")
	await _teardown(ctx)


func _check_scouting_choice() -> void:
	print("[the choice at each group]")
	var ctx := await _setup()
	var dm = ctx.dm
	var groups := _groups(dm, 6)

	# Keep waiting through the whole watch.
	dm.scouting.begin(dm.rivals(), _rng(1), ctx.player)
	var total := 0
	_check(ctx.player.input_locked, "the player is held still during the watch")
	_check(
		dm.actions_for(ctx.player.tile, ctx.player.facing_delta(), ctx.player).size() == 2,
		"only the two choices are on offer"
	)
	while dm.scouting.active:
		total += 1
		dm.scouting.wait()
	_check(total >= 2, "all the groups were shown")
	_check(_requested.is_empty(), "waiting through all of them starts no encounter")
	_check(not ctx.player.input_locked, "the player moves again")
	_check(
		not _messages.is_empty() and _messages[-1] == tr("UI_SCOUT_NONE_LEFT"),
		"the player is told no other group is wandering here"
	)

	# Take the second group on.
	_messages.clear()
	dm.scouting.begin(dm.rivals(), _rng(1), ctx.player)
	dm.scouting.wait()
	var chosen = dm.scouting.current()
	var engage: Callable = dm.scouting.actions()[0].callable
	engage.call()
	_check(_requested.size() == 1 and _requested[0] == chosen, "the shown group is taken on")
	_check(not dm.scouting.active and dm.scouting.current() == null, "no further group is shown")
	_check(not ctx.player.input_locked, "the transformation is over")
	_check(not _messages.has(tr("UI_SCOUT_NONE_LEFT")), "and no 'no other group' message is said")
	_check(groups.size() == dm.rivals().size(), "the other groups are left alone")

	# Out of a watch, the choices are not on offer and engaging does nothing.
	_requested.clear()
	dm.scouting.engage()
	dm.scouting.wait()
	_check(_requested.is_empty(), "engage and wait do nothing outside a watch")
	_check(dm.scouting.actions().is_empty(), "no choice is offered outside a watch")
	await _teardown(ctx)


func _check_scouting_edges() -> void:
	print("[a map with few or no groups]")
	var ctx := await _setup()
	var dm = ctx.dm
	dm.scouting.begin(dm.rivals(), _rng(3), ctx.player)
	_check(not dm.scouting.active and not ctx.player.input_locked, "no group: no watch")
	_check(_messages.has(tr("UI_SCOUT_NONE_LEFT")), "no group: the player is told")

	_groups(dm, 1)
	dm.scouting.begin(dm.rivals(), _rng(3), ctx.player)
	var shown := 0
	while dm.scouting.active:
		shown += 1
		dm.scouting.wait()
	_check(shown == 1, "one group on the map: one group shown (%d)" % shown)
	await _teardown(ctx)

	# Exact makeup: number and species.
	ctx = await _setup()
	dm = ctx.dm
	_group(dm, Vector3i(2, 0, 2), [&"mastel", &"mastel", &"ravbak"])
	dm.scouting.begin(dm.rivals(), _rng(3), ctx.player)
	var text: String = dm.scouting.description()
	var mastel: String = tr(GameData.species(&"mastel").name_key())
	var ravbak: String = tr(GameData.species(&"ravbak").name_key())
	_check(("2 x %s" % mastel) in text, "the exact number of a species is shown (%s)" % text)
	_check(("1 x %s" % ravbak) in text, "and each species in the group")
	_check(not ("kalilk" in text), "and nothing that is not in it")
	dm.scouting.end()
	await _teardown(ctx)


## The ability, and the HUD that offers the choice.
func _check_scouting_surfaces() -> void:
	print("[the ability and the HUD]")
	var ctx := await _setup()
	var dm = ctx.dm
	_groups(dm, 4)
	var used: bool = StaticCamouflage.new().use(ExplorationContext.new(dm, ctx.player, _rng(5)))
	_check(used and dm.scouting.active, "using Static Camouflage starts the watch")

	var hud = ctx.scene.get_node("HudExploration")
	await get_tree().process_frame
	await get_tree().process_frame
	hud._refresh_actions()
	_check(
		hud._action_menu.selected_id() == &"scout_engage",
		"the HUD offers the choice, and nothing else"
	)
	hud._update_status()
	_check(
		dm.scouting.description() in hud._status_label.text,
		"the HUD keeps the group on screen while the choice is pending"
	)
	hud._action_menu.cycle(1)
	hud._action_menu.confirm()
	_check(_requested.is_empty() and dm.scouting.active, "Keep waiting shows the next group")
	hud._action_menu.cycle(-1)
	hud._action_menu.confirm()
	_check(
		_requested.size() == 1 and not dm.scouting.active, "Take this group on opens its encounter"
	)
	hud._refresh_actions()
	_check(hud._action_menu.selected_id() != &"scout_engage", "the usual menu is back afterwards")
	await _teardown(ctx)
