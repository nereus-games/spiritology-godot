## Headless check of the Coal Vetch, through both of its entrances.
##
## In an encounter: repeated Examines of one rival call an agent at the configured threshold and
## chance, at most once; Steal runs the risk too, and fails while an agent is there; an agent's
## presence cuts a player character's Examine yield; the dice are the agent's own.
##
## In a dungeon: the arrivals happen on their turns, on their tiles; an agent walks the shortest
## path to the player, across floors by staircase; meeting it opens no encounter; the corruptible
## agent delays the agents still to come, for a price that rises each time; the data round-trips.
##
## Runs the "stairs" scenario for its two floors; the dungeon config is built here, so no data file
## has to carry level content for it.
##
## Run with: Godot --headless --path . res://scenes/dev/coal_vetch_check.tscn
## As a start scene rather than --script; see geometry_check.gd.
extends Node

const ScenarioCatalog := preload("res://scripts/dev/scenario_catalog.gd")
const EXPLORATION := preload("res://scenes/exploration/exploration.tscn")
const CoalVetch := preload("res://scripts/exploration/coal_vetch.gd")

var _fails: Array[String] = []
var _balance: BalanceData
var _saved := {}

const BALANCE_FIELDS := [
	"coal_vetch_examine_threshold",
	"coal_vetch_examine_chance",
	"coal_vetch_steal_appear_chance",
	"coal_vetch_steal_fail_chance",
	"coal_vetch_examine_factor",
	"coal_vetch_delay_turns",
	"coal_vetch_bribe_base",
	"coal_vetch_bribe_step",
	"coal_vetch_catch_den",
]


## Plays queued actions, then passes.
class Player:
	extends EncounterAgent
	var queued: Array = []

	func decide(individual: EncounterIndividual, _manager: EncounterManager) -> EncounterAction:
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
	_balance = BalanceData.current()
	for f in BALANCE_FIELDS:
		_saved[f] = _balance.get(f)
	await _check_examines()
	await _check_steal()
	await _check_dice_are_its_own()
	await _check_dungeon()
	for f in BALANCE_FIELDS:
		_balance.set(f, _saved[f])
	print("")
	if _fails.is_empty():
		print("ALL OK")
	else:
		print("FAILURES: %s" % [_fails])
	get_tree().quit(0 if _fails.is_empty() else 1)


# --------------------------------------------------------------------------
# In an encounter
# --------------------------------------------------------------------------


func _examine(target: EncounterIndividual) -> EncounterAction:
	return EncounterAction.of_kind(EncounterAction.Kind.EXAMINE, [target])


func _steal(target: EncounterIndividual) -> EncounterAction:
	return EncounterAction.of_kind(EncounterAction.Kind.STEAL, [target])


## Two players and two rivals in the order [p0, p1, r0, r1].
func _encounter(seed := 20261029) -> EncounterManager:
	var all: Array = []
	for id in [&"kalilk", &"fliritus"]:
		all.append(EncounterManager.make_individual(id, true))
	for id in [&"skorpis", &"skorpis"]:
		all.append(EncounterManager.make_individual(id, false))
	var m := EncounterManager.new()
	m.setup([all[0], all[1]], [all[2], all[3]], seed)
	m.timeline.order = all.duplicate()
	for f in all:
		m.set_agent(f, Player.new())
		f.eth = 20
	return m


func _play(m: EncounterManager, who: EncounterIndividual, actions: Array) -> void:
	(m.agent_for(who) as Player).queued = actions


## The causes of every agent announced.
func _appearances(m: EncounterManager) -> Array:
	var seen: Array = []
	m.agent_appeared.connect(func(cause): seen.append(cause))
	return seen


func _check_examines() -> void:
	print("[repeated Examines]")
	_balance.coal_vetch_examine_threshold = 2
	_balance.coal_vetch_examine_chance = 1.0
	var m := _encounter()
	var p0: EncounterIndividual = m.players[0]
	var p1: EncounterIndividual = m.players[1]
	var seen := _appearances(m)
	_play(m, p0, [_examine(m.rivals[0]), _examine(m.rivals[1])])
	await m.run(2)
	_check(seen.is_empty(), "one Examine of each of two rivals calls nobody")
	_check(not m.coal_vetch_present, "...and no agent is present")
	m.free()

	m = _encounter()
	p0 = m.players[0]
	seen = _appearances(m)
	_play(m, p0, [_examine(m.rivals[0]), _examine(m.rivals[0]), _examine(m.rivals[0])])
	await m.run(3)
	_check(seen == [&"examines"], "the second Examine of one rival calls an agent, once (%s)" % [seen])
	_check(m.coal_vetch_present, "...which is then present")
	m.free()

	# A rival's Examine does not count, and neither does one on a teammate.
	m = _encounter()
	var r0: EncounterIndividual = m.rivals[0]
	var r1: EncounterIndividual = m.rivals[1]
	seen = _appearances(m)
	_play(m, r0, [_examine(m.players[0]), _examine(m.players[0]), _examine(m.players[0])])
	await m.run(3)
	_check(seen.is_empty(), "a rival's Examines call nobody")
	m.free()

	# The chance is what decides it.
	_balance.coal_vetch_examine_chance = 0.0
	m = _encounter()
	p0 = m.players[0]
	seen = _appearances(m)
	_play(m, p0, [_examine(m.rivals[0]), _examine(m.rivals[0]), _examine(m.rivals[0])])
	await m.run(3)
	_check(seen.is_empty(), "at a chance of 0, repeated Examines call nobody")
	m.free()

	# The threshold too.
	_balance.coal_vetch_examine_chance = 1.0
	_balance.coal_vetch_examine_threshold = 3
	m = _encounter()
	p0 = m.players[0]
	seen = _appearances(m)
	_play(m, p0, [_examine(m.rivals[0]), _examine(m.rivals[0])])
	await m.run(2)
	_check(seen.is_empty(), "at a threshold of 3, two Examines call nobody")
	m.free()

	# The yield, while an agent is there.
	_balance.coal_vetch_examine_threshold = 2
	_balance.coal_vetch_examine_factor = 0.5
	m = _encounter()
	p0 = m.players[0]
	var before := m.examine_factor(p0, m.rivals[0])
	m.coal_vetch_present = true
	_check(
		is_equal_approx(m.examine_factor(p0, m.rivals[0]), before * 0.5),
		"an agent's presence halves a player character's Examine"
	)
	_check(
		is_equal_approx(m.examine_factor(m.rivals[0], p0), before),
		"...and leaves a rival's alone"
	)
	m.free()


func _check_steal() -> void:
	print("[Steal]")
	_balance.coal_vetch_steal_appear_chance = 1.0
	_balance.coal_vetch_steal_fail_chance = 1.0
	var m := _encounter()
	var p0: EncounterIndividual = m.players[0]
	var seen := _appearances(m)
	var lines: Array = []
	m.turn_taken.connect(func(_who, _action, l): lines.append_array(l))
	_play(m, p0, [_steal(m.rivals[0])])
	await m.run(1)
	var target: String = m.rivals[0].display_name()
	_check(seen == [&"steal"], "Steal can call an agent (%s)" % [seen])
	_check(
		lines.has(m.tr("LOG_STEAL_FAILS_VETCH") % target),
		"...and fails while the agent is there, at a failure chance of 1"
	)
	m.free()

	_balance.coal_vetch_steal_fail_chance = 0.0
	m = _encounter()
	p0 = m.players[0]
	lines = []
	m.turn_taken.connect(func(_who, _action, l): lines.append_array(l))
	_play(m, p0, [_steal(m.rivals[0])])
	await m.run(1)
	_check(
		lines.has(m.tr("LOG_STEAL") % m.rivals[0].display_name()),
		"at a failure chance of 0, it goes through"
	)
	m.free()

	_balance.coal_vetch_steal_appear_chance = 0.0
	_balance.coal_vetch_steal_fail_chance = 1.0
	m = _encounter()
	p0 = m.players[0]
	seen = _appearances(m)
	lines = []
	m.turn_taken.connect(func(_who, _action, l): lines.append_array(l))
	_play(m, p0, [_steal(m.rivals[0])])
	await m.run(1)
	_check(
		seen.is_empty() and not lines.has(m.tr("LOG_STEAL_FAILS_VETCH") % target),
		"with no risk of an agent, there is none to make it fail"
	)
	m.free()


## The same seed gives the same encounter whether an agent can come or not: its dice are its own.
func _check_dice_are_its_own() -> void:
	print("[the agent's own dice]")
	_balance.coal_vetch_examine_chance = 0.0
	var first: int = await _roll_after_examines(0.0)
	var second: int = await _roll_after_examines(1.0)
	_check(first == second, "the encounter's own random draws do not depend on the agent")


func _roll_after_examines(chance: float) -> int:
	_balance.coal_vetch_examine_chance = chance
	var m := _encounter(777)
	_play(m, m.players[0], [_examine(m.rivals[0]), _examine(m.rivals[0]), _examine(m.rivals[0])])
	await m.run(3)
	var draw := m.rng.randi()
	m.free()
	return draw


# --------------------------------------------------------------------------
# In a dungeon
# --------------------------------------------------------------------------


func _arrival(tile: Vector3i, turn: int) -> CoalVetchArrival:
	var a := CoalVetchArrival.new()
	a.tile = tile
	a.turn = turn
	return a


func _config(arrivals: Array, corruptible := false) -> DungeonConfig:
	var cfg := DungeonConfig.new()
	cfg.id = &"vetch_check"
	for a in arrivals:
		cfg.coal_vetch_arrivals.append(a)
	cfg.has_corruptible_agent = corruptible
	cfg.corruptible_agent_tile = Vector3i(3, 0, 2)
	return cfg


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _check_dungeon() -> void:
	ScenarioCatalog.selected_id = &"stairs"
	var scene = EXPLORATION.instantiate()
	get_tree().root.add_child(scene)
	await get_tree().process_frame
	var dm: DungeonManager = scene.get_node("DungeonManager")
	var player = scene.get_node("Player")
	_balance.coal_vetch_delay_turns = 20
	_balance.coal_vetch_bribe_base = 1
	_balance.coal_vetch_bribe_step = 1
	_balance.coal_vetch_catch_den = 20

	await _check_config_roundtrip()
	_check_arrivals(dm)
	_check_shortest_path(dm)
	await _check_pursuit(dm, player)
	_check_contact(dm)
	_check_bribes(dm)
	scene.queue_free()
	await get_tree().process_frame


func _check_config_roundtrip() -> void:
	print("[the data side]")
	var cfg := _config([_arrival(Vector3i(0, 0, 0), 5), _arrival(Vector3i(7, 0, 12), 9)], true)
	var path := "user://vetch_check_config.tres"
	_check(ResourceSaver.save(cfg, path) == OK, "a dungeon config with arrivals saves")
	var back = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	_check(
		back != null and back.coal_vetch_arrivals.size() == 2,
		"...and loads back with its arrivals"
	)
	if back != null:
		_check(
			back.coal_vetch_arrivals[1].tile == Vector3i(7, 0, 12)
			and back.coal_vetch_arrivals[1].turn == 9
			and back.has_corruptible_agent
			and back.corruptible_agent_tile == Vector3i(3, 0, 2),
			"...tiles, turns and the corruptible agent intact"
		)
	DirAccess.remove_absolute(path)


func _check_arrivals(dm: DungeonManager) -> void:
	print("[arrivals]")
	var v := CoalVetch.new(_config([_arrival(Vector3i(0, 0, 0), 3), _arrival(Vector3i(7, 0, 12), 5)]), dm)
	_check(v.pending_count() == 2 and v.next_due() == 3, "two arrivals are pending, the first on turn 3")
	_check(v.on_turn(1).is_empty() and v.on_turn(2).is_empty(), "nobody comes before the turn")
	var came := v.on_turn(3)
	_check(came.size() == 1, "one agent on turn 3")
	_check(came[0].tile == Vector3i(0, 0, 0), "...on its arrival tile")
	_check(dm.agents().size() == 1 and dm.rivals().is_empty(), "...an agent, not a rival group")
	_check(v.on_turn(4).is_empty(), "nobody on turn 4")
	came += v.on_turn(5)
	_check(came.size() == 2 and came[1].tile == Vector3i(7, 0, 12), "the second, on its own tile, on 5")
	_check(v.pending_count() == 0 and v.arrived == 2, "nothing left to come")
	for a in dm.agents():
		a.remove_from_dungeon()


func _check_shortest_path(dm: DungeonManager) -> void:
	print("[shortest path]")
	var flat := dm.tile_search.shortest_path(Vector3i(0, 0, 0), Vector3i(3, 0, 5))
	var steps: Dictionary = dm.tile_search.walking_distances(Vector3i(0, 0, 0), 20)
	_check(flat.size() - 1 == steps[Vector3i(3, 0, 5)], "on one floor, as long as the shortest walk")
	var up := dm.tile_search.shortest_path(Vector3i(0, 0, 0), Vector3i(1, 1, 6))
	_check(up.size() == 7, "to the floor above: 7 tiles (%d)" % up.size())
	var at := up.find(Vector3i(1, 0, 3))
	_check(
		at >= 0 and at + 1 < up.size() and up[at + 1] == Vector3i(1, 1, 5),
		"...by the staircase, which is one step"
	)
	_check(
		dm.tile_search.shortest_path(Vector3i(0, 0, 0), Vector3i(50, 0, 50)).is_empty(),
		"no path to nowhere"
	)


func _check_pursuit(dm: DungeonManager, player) -> void:
	print("[pursuit]")
	var goal := Vector3i(1, 1, 6)
	player.teleport_to(goal)
	var route := dm.tile_search.shortest_path(Vector3i(0, 0, 0), goal, true)
	var v := CoalVetch.new(_config([_arrival(Vector3i(0, 0, 0), 2)]), dm)
	dm.advance_turn()
	v.on_turn(dm.turn_count)
	dm.advance_turn()
	v.on_turn(dm.turn_count)
	var agent: Node = dm.agents()[0] if not dm.agents().is_empty() else null
	_check(agent != null, "the agent is there on turn 2")
	if agent == null:
		return
	var caught: Array = []
	dm.agent_caught_player.connect(func(a): caught.append(a))
	var encounters: Array = []
	dm.encounter_requested.connect(func(r, _by): encounters.append(r))
	var followed := true
	var guard := 0
	while caught.is_empty() and guard < 20:
		guard += 1
		var before: Vector3i = agent.tile
		dm.advance_turn()
		await _wait(0.3)
		if agent.tile != before and route.find(agent.tile) != route.find(before) + 1:
			followed = false
	_check(not caught.is_empty(), "it reaches the player (%d turns)" % guard)
	_check(followed, "...every step along the shortest path, the staircase included")
	_check(encounters.is_empty(), "...and no encounter opens")
	_check(
		guard == route.size() - 1 + 1 or guard == route.size(),
		"...in as many turns as the path has steps, after its arrival turn (%d for %d)"
		% [guard, route.size() - 1]
	)

	# The toll.
	GameSession.set_den(GameSession.PartySlot.MAIN, 100)
	GameSession.set_den(GameSession.PartySlot.TEAMMATE, 10)
	var taken := v.catch_player(agent)
	_check(GameSession.get_den(GameSession.PartySlot.MAIN) == 80, "the toll is 20 DEN from each")
	_check(GameSession.get_den(GameSession.PartySlot.TEAMMATE) == 1, "...but never takes anyone down to 0")
	_check(taken == 20, "...reporting the larger toll")
	await get_tree().process_frame
	_check(dm.agents().is_empty(), "...and the agent leaves")
	GameSession.set_den(GameSession.PartySlot.MAIN, 100)
	GameSession.set_den(GameSession.PartySlot.TEAMMATE, 100)
	for c in dm.agent_caught_player.get_connections():
		dm.agent_caught_player.disconnect(c.callable)
	for c in dm.encounter_requested.get_connections():
		if c.callable.get_object() == null or c.callable.get_object() == self:
			dm.encounter_requested.disconnect(c.callable)
	player.teleport_to(Vector3i(3, 0, 0))


func _check_contact(dm: DungeonManager) -> void:
	print("[walking into an agent]")
	var v := CoalVetch.new(_config([_arrival(Vector3i(5, 0, 5), 1)]), dm)
	var agent: Node = v.on_turn(1)[0]
	var caught: Array = []
	var encounters: Array = []
	dm.agent_caught_player.connect(func(a): caught.append(a))
	dm.encounter_requested.connect(func(r, _by): encounters.append(r))
	dm.request_encounter(agent, false)
	_check(caught == [agent] and encounters.is_empty(), "the player's step into it catches them, no encounter")
	agent.remove_from_dungeon()
	for c in dm.agent_caught_player.get_connections():
		dm.agent_caught_player.disconnect(c.callable)
	for c in dm.encounter_requested.get_connections():
		if c.callable.get_object() == self:
			dm.encounter_requested.disconnect(c.callable)


func _check_bribes(dm: DungeonManager) -> void:
	print("[the corruptible agent]")
	var v := CoalVetch.new(_config([_arrival(Vector3i(0, 0, 0), 10), _arrival(Vector3i(7, 0, 12), 20)], true), dm)
	var mech = v.populate()
	_check(mech != null and dm.mechanisms_at(Vector3i(3, 0, 2)).has(mech), "it stands on its tile")
	_check(mech.blocks_walk(), "...an obstacle")
	_check(
		CoalVetch.new(_config([_arrival(Vector3i(0, 0, 0), 10)]), dm).populate() == null,
		"a dungeon without one places none"
	)
	var messages: Array = []
	dm.message_posted.connect(func(t): messages.append(t))

	GameSession.inventory.clear()
	_check(v.price() == 1, "the first price is the base")
	_check(not mech.bribe() and v.bribes == 0 and v.next_due() == 10, "with nothing to pay with, nothing happens")
	_check(messages.back() == mech.tr("UI_VETCH_BRIBE_POOR") % 1, "...and it says what it wants")
	_check(mech.on_adjacent_actions(null, Vector3i.ZERO).size() == 1, "the bribe is on offer")

	GameSession.add_object(&"notice", 3)
	GameSession.add_object(&"rune_stone", 2)
	_check(not v.pay({&"notice": 5}), "an explicit payment of the wrong size is refused")
	_check(not v.pay({&"smoke_bomb": 1}), "...and so is one of objects not held")
	_check(v.bribes == 0 and GameSession.object_count(&"notice") == 3, "...changing nothing")
	_check(mech.bribe(), "paid")
	_check(GameSession.object_count(&"notice") == 2, "...from the biggest stack")
	_check(v.next_due() == 30, "...every pending arrival is delayed by 20 turns")
	_check(v.price() == 2, "the price rises")
	_check(mech.bribe(), "paid again")
	_check(v.next_due() == 50 and v.price() == 3, "...delayed again (50), dearer again (3)")
	_check(v.objects_held() == 2 and not v.can_bribe(), "two objects left cannot pay 3")
	GameSession.add_object(&"notice", 1)
	_check(v.can_bribe(), "a third object can")
	var came := v.on_turn(30)
	_check(came.is_empty(), "turn 30 brings nobody: the first arrival was delayed twice")
	came = v.on_turn(50)
	_check(came.size() == 1, "...and turn 50 brings the first")
	came = v.on_turn(60)
	_check(came.size() == 1, "...turn 60 the second, delayed the same")
	_check(mech.on_adjacent_actions(null, Vector3i.ZERO).is_empty(), "nobody left to delay: no bribe on offer")
	_check(not v.pay(), "...and no payment taken")
	for a in dm.agents():
		a.remove_from_dungeon()
	mech.queue_free()
	GameSession.inventory.clear()
