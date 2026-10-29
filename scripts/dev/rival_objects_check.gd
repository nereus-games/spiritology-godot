## Headless check of rivals carrying objects: the roll at spawn (from the variety's loot), the map
## state that carries them into an encounter and back, Examine revealing them, Steal taking one,
## Altruism destroying one, and Misty Secret's weight on using objects making a rival use one.
##
## Run with: Godot --headless --path . res://scenes/dev/rival_objects_check.tscn
## As a start scene rather than --script; see geometry_check.gd.
extends Node

const RivalSpawner := preload("res://scripts/exploration/rival_spawner.gd")
const RivalMember := preload("res://scripts/exploration/rival_member.gd")
const ABILITY_DIR := "res://data/abilities/"

var _fails: Array[String] = []


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
	_check_spawn()
	_check_map_state()
	await _check_examine()
	await _check_steal()
	await _check_altruism()
	await _check_object_use()
	print("")
	if _fails.is_empty():
		print("ALL OK")
	else:
		print("FAILURES: %s" % [_fails])
	get_tree().quit(0 if _fails.is_empty() else 1)


# --------------------------------------------------------------------------
# Scaffolding
# --------------------------------------------------------------------------


## [p0, p1, r0, r1], everyone passing until told otherwise. The first rival carries a rune stone
## and a notice, the second nothing. The caller frees it.
func _encounter(seed := 20261029) -> EncounterManager:
	var all: Array = []
	for id in [&"kalilk", &"fliritus"]:
		all.append(EncounterManager.make_individual(id, true))
	for id in [&"ravbak", &"skorpis"]:
		all.append(EncounterManager.make_individual(id, false))
	var m := EncounterManager.new()
	m.setup([all[0], all[1]], [all[2], all[3]], seed)
	m.timeline.order = all.duplicate()
	m.object_provider = func(id): return load("res://data/objects/%s.tres" % id)
	for f in all:
		m.set_agent(f, Player.new())
		f.eth = 20
	all[2].carried_objects.assign([&"rune_stone", &"notice"])
	return m


func _play(m: EncounterManager, who: EncounterIndividual, action: EncounterAction) -> void:
	(m.agent_for(who) as Player).queued = [action]


func _kind(kind: EncounterAction.Kind, target: EncounterIndividual) -> EncounterAction:
	return EncounterAction.of_kind(kind, [target])


func _listen(m: EncounterManager) -> Array:
	var heard: Array = []
	m.turn_taken.connect(func(_who, _action, lines): heard.append_array(lines))
	return heard


func _tr(key: String) -> String:
	return String(TranslationServer.translate(key))


# --------------------------------------------------------------------------
# Spawning and the map
# --------------------------------------------------------------------------


func _check_spawn() -> void:
	print("[spawn]")
	var config := DungeonConfig.new()
	config.possible_species.assign([&"draka", &"erdouss"])
	config.group_size_min = 2
	config.group_size_max = 2
	var spawner = RivalSpawner.new(config, null, 20261029)
	var loot := {
		&"draka": [&"rune_stone", &"smoke_bomb", &"spade"],
		&"erdouss": [&"tea_drop"],
	}
	var in_loot := true
	var carried := 0
	var members := 0
	for i in 200:
		for m in spawner.roll_composition():
			members += 1
			carried += m.objects.size()
			for id in m.objects:
				if not loot[m.species_id].has(id):
					in_loot = false
	_check(in_loot, "a rival carries only objects its variety may drop")
	_check(carried > 0, "...and some carry some (%d objects on %d rivals)" % [carried, members])
	_check(carried < members * 3, "...but not all of them everywhere")
	var a: Array = RivalSpawner.new(config, null, 7).roll_composition()
	var b: Array = RivalSpawner.new(config, null, 7).roll_composition()
	var same := a.size() == b.size()
	for i in mini(a.size(), b.size()):
		same = same and a[i].objects == b[i].objects
	_check(same, "the same seed rolls the same objects")
	_check(spawner.roll_objects(&"no_such_variety").is_empty(), "an unknown variety carries nothing")


func _check_map_state() -> void:
	print("[map state]")
	var member := RivalMember.new(&"ravbak", 50, 50)
	_check(not member.encounter_state().has("objects"), "a rival with nothing says nothing")
	member.objects.assign([&"spade", &"notice"])
	member.objects_known = true
	var state := member.encounter_state()
	_check(state["objects"] == [&"spade", &"notice"], "its objects ride into the encounter")
	_check(state["objects_known"] == true, "...and so does what Examine revealed")
	var back := RivalMember.new(&"ravbak", 50, 50)
	back.take_encounter_state({"den": 10, "eth": 10, "objects": [&"notice"], "objects_known": true})
	_check(back.objects == [&"notice"], "what is stolen stays stolen")
	_check(back.objects_known, "...and what was revealed stays revealed")
	var untouched := RivalMember.new(&"ravbak", 50, 50)
	untouched.objects.assign([&"spade"])
	untouched.take_encounter_state({"den": 10, "eth": 10})
	_check(untouched.objects == [&"spade"], "a report that says nothing of objects changes none")


# --------------------------------------------------------------------------
# The encounter
# --------------------------------------------------------------------------


func _check_examine() -> void:
	print("[examine]")
	var m := _encounter()
	var heard := _listen(m)
	var r0: EncounterIndividual = m.rivals[0]
	_check(not r0.objects_known, "unexamined, the objects are not known")
	_play(m, m.players[0], _kind(EncounterAction.Kind.EXAMINE, r0))
	await m.run(1)
	_check(r0.objects_known, "Examine reveals the rival's objects")
	var names := "%s, %s" % [_tr("OBJECT_RUNE_STONE_NAME"), _tr("OBJECT_NOTICE_NAME")]
	_check(
		heard.has(_tr("LOG_EXAMINE_OBJECTS") % [r0.display_name(), names]),
		"...and says which, by name"
	)
	_check(not m.rivals[1].objects_known, "the other rival is not revealed")
	m.free()

	m = _encounter()
	heard = _listen(m)
	var r1: EncounterIndividual = m.rivals[1]
	_play(m, m.players[0], _kind(EncounterAction.Kind.EXAMINE, r1))
	await m.run(1)
	_check(
		heard.has(_tr("LOG_EXAMINE_NO_OBJECTS") % r1.display_name()),
		"a rival carrying nothing is said to carry nothing"
	)
	m.free()

	m = _encounter()
	_play(m, m.rivals[0], _kind(EncounterAction.Kind.EXAMINE, m.players[0]))
	await m.run(1)
	_check(not m.players[0].objects_known, "a player character has nothing to reveal")
	m.free()

	m = _encounter()
	var report: Array = m.rival_report()
	_check(report[0]["objects"] == [&"rune_stone", &"notice"], "the report carries the objects")
	_check(report[0]["objects_known"] == false, "...and whether they are known")
	m.free()


func _check_steal() -> void:
	print("[steal]")
	var m := _encounter()
	var taken: Array = []
	m.object_obtained.connect(func(id): taken.append(id))
	var heard := _listen(m)
	var r0: EncounterIndividual = m.rivals[0]
	_play(m, m.players[0], _kind(EncounterAction.Kind.STEAL, r0))
	await m.run(1)
	_check(taken.size() == 1, "a player character's Steal hands one object over")
	var one: StringName = taken[0] if not taken.is_empty() else &""
	_check([&"rune_stone", &"notice"].has(one), "...one the rival carried")
	_check(r0.carried_objects.size() == 1 and not r0.carried_objects.has(one), "...and gone from it")
	_check(
		heard.has(_tr("LOG_STEAL_TAKEN") % [r0.display_name(), m._object_name(one)]),
		"...and the log names it"
	)
	m.free()

	m = _encounter()
	taken.clear()
	m.object_obtained.connect(func(id): taken.append(id))
	heard = _listen(m)
	var r1: EncounterIndividual = m.rivals[1]
	_play(m, m.players[0], _kind(EncounterAction.Kind.STEAL, r1))
	await m.run(1)
	_check(taken.is_empty(), "nothing is taken from a rival carrying nothing")
	_check(heard.has(_tr("LOG_STEAL_NOTHING") % r1.display_name()), "...and the log says so")
	m.free()

	m = _encounter()
	var stolen_ids: Array = []
	m.object_obtained.connect(func(id): stolen_ids.append(id))
	(m.agent_for(m.players[0]) as Player).queued = [
		_kind(EncounterAction.Kind.STEAL, m.rivals[0]),
		_kind(EncounterAction.Kind.STEAL, m.rivals[0]),
		_kind(EncounterAction.Kind.STEAL, m.rivals[0]),
	]
	await m.run(3)
	_check(
		stolen_ids.size() == 2, "a rival can be robbed of what it carries and no more (%s)" % [stolen_ids]
	)
	m.free()


func _check_altruism() -> void:
	print("[altruism]")
	var altruism: AbilityData = load(ABILITY_DIR + "altruism.tres")

	# A player character pays from the inventory it is given a view of.
	var m := _encounter()
	var inventory := {&"notice": 2, &"spade": 1}
	var consumed: Array = []
	m.inventory_view = func() -> Dictionary: return inventory.duplicate()
	m.object_consumed.connect(func(id): consumed.append(id))
	var p0: EncounterIndividual = m.players[0]
	p0.den = 40
	_play(m, m.players[1], EncounterAction.use_ability(altruism, [p0]))
	await m.run(1)
	_check(p0.den > 40, "the target is healed")
	_check(consumed == [&"notice"], "...at the price of an object, announced (%s)" % [consumed])
	m.free()

	# With nothing to destroy, it is not usable, and does nothing if forced.
	m = _encounter()
	p0 = m.players[0]
	p0.den = 40
	_check(not m.can_play(m.players[1], altruism), "unusable when the players own nothing")
	_play(m, m.players[1], EncounterAction.use_ability(altruism, [p0]))
	await m.run(1)
	_check(p0.den == 40, "...and heals nothing if played anyway")
	m.free()

	# A rival pays with what it carries.
	m = _encounter()
	var r0: EncounterIndividual = m.rivals[0]
	r0.den = 30
	_check(m.can_play(r0, altruism), "a rival carrying objects can play it")
	_check(not m.can_play(m.rivals[1], altruism), "...one carrying none cannot")
	_play(m, r0, EncounterAction.use_ability(altruism, [r0]))
	await m.run(1)
	_check(r0.den > 30, "the rival heals itself")
	_check(r0.carried_objects.size() == 1, "...and has one object fewer")
	m.free()


func _check_object_use() -> void:
	print("[misty secret and the use of objects]")
	var misty: AbilityData = load(ABILITY_DIR + "misty_secret.tres")
	var step := BalanceData.current().action_weight_bonus
	var runs := 80
	var used := 0
	for i in runs:
		var m := _encounter(1000 + i)
		var r0: EncounterIndividual = m.rivals[0]
		r0.carried_objects.assign([&"rune_stone"])
		m.set_agent(r0, m.default_agent)
		_play(m, m.players[0], EncounterAction.use_ability(misty, []))
		await m.run(1)
		if r0.carried_objects.is_empty():
			used += 1
		m.free()
	_check(used > 0, "a rival carrying an object uses it (%d of %d)" % [used, runs])
	_check(
		absf(float(used) / runs - step) < 0.2,
		"...about as often as the weight says (%d of %d, weight %.2f)" % [used, runs, step]
	)

	# Without the weight a rival never reaches for an object.
	var spent := 0
	for i in runs:
		var m := _encounter(3000 + i)
		var r0: EncounterIndividual = m.rivals[0]
		m.set_agent(r0, m.default_agent)
		await m.run(1)
		if r0.carried_objects.size() < 2:
			spent += 1
		m.free()
	_check(spent == 0, "without the weight a rival uses nothing")

	# A weight on a rival carrying nothing is recorded and inert.
	var m := _encounter()
	var r1: EncounterIndividual = m.rivals[1]
	r1.add_action_weight(EncounterAction.Kind.USE_OBJECT, 1.0, m.players[0], 2)
	m.set_agent(r1, m.default_agent)
	var tries: Array = []
	m.turn_taken.connect(
		func(_who, action, _lines): tries.append(action.kind == EncounterAction.Kind.USE_OBJECT)
	)
	await m.run(1)
	_check(not tries.has(true), "a weighted rival carrying nothing does not try to use one")
	m.free()

	# What it uses is spent from its own belongings, never the players' inventory.
	m = _encounter()
	var consumed: Array = []
	m.object_consumed.connect(func(id): consumed.append(id))
	var r0: EncounterIndividual = m.rivals[0]
	r0.add_action_weight(EncounterAction.Kind.USE_OBJECT, 1.0, m.players[0], 2)
	m.set_agent(r0, m.default_agent)
	await m.run(1)
	_check(r0.carried_objects.size() == 1, "a certain draw spends one of its objects")
	_check(consumed.is_empty(), "...and touches no inventory")
	m.free()
