## Headless check of the weighted rival choices: an ability makes rivals Talk, Meditate or use
## objects "more often", and the rival's automatic choice takes it into account. Radiant Secret,
## Hyping Up, Misty Secret, One's Ethos and Business Card — each one played through real rounds
## with seeds fixed in advance, with someone it must touch and someone it must leave alone.
##
## Run with: Godot --headless --path . res://scenes/dev/weights_check.tscn
## As a start scene rather than --script; see geometry_check.gd.
extends Node

const ABILITY_DIR := "res://data/abilities/"
const TALK := EncounterAction.Kind.TALK
const MEDITATE := EncounterAction.Kind.MEDITATE

var _fails: Array[String] = []


## Plays queued actions, then passes.
class Player:
	extends EncounterAgent
	var queued: Array = []
	var spy: Callable = Callable()

	func decide(individual: EncounterIndividual, _manager: EncounterManager) -> EncounterAction:
		if spy.is_valid():
			spy.call()
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
	await _check_radiant_secret()
	await _check_hyping_up()
	await _check_misty_secret()
	await _check_ones_ethos()
	await _check_business_card()
	await _check_no_weight_no_draw()
	await _check_same_seed_same_choices()
	print("")
	if _fails.is_empty():
		print("ALL OK")
	else:
		print("FAILURES: %s" % [_fails])
	get_tree().quit(0 if _fails.is_empty() else 1)


# --------------------------------------------------------------------------
# Scaffolding
# --------------------------------------------------------------------------


## Two players and two rivals in the order [p0, p1, r0, r1]. Only the players are scripted: the
## rivals keep the default AutoAgent, which is what is under test. The caller frees it.
func _encounter(player_ids: Array, rival_ids: Array, seed: int) -> EncounterManager:
	var ps: Array = []
	var rs: Array = []
	for id in player_ids:
		ps.append(EncounterManager.make_individual(id, true))
	for id in rival_ids:
		rs.append(EncounterManager.make_individual(id, false))
	var m := EncounterManager.new()
	m.setup(ps, rs, seed)
	m.timeline.order = ps + rs
	for p in ps:
		m.set_agent(p, Player.new())
	return m


func _ability(id: StringName) -> AbilityData:
	return load(ABILITY_DIR + "%s.tres" % id)


func _play(m: EncounterManager, who: EncounterIndividual, ability: AbilityData, target) -> void:
	(m.agent_for(who) as Player).queued = [EncounterAction.use_ability(ability, [target])]


## Plays `runs` encounters of one round, the user (players[user_index]) using `ability` on
## rivals[aim]. Returns, for each rival, how often it Talked, Meditated and Talked to the user.
func _sample(
	player_ids: Array,
	rival_ids: Array,
	user_index: int,
	ability_id: StringName,
	aim: int,
	runs: int
) -> Dictionary:
	var out := {"talk": [0, 0], "meditate": [0, 0], "talk_at_user": [0, 0]}
	for seed in range(runs):
		var m := _encounter(player_ids, rival_ids, 1000 + seed)
		var user: EncounterIndividual = m.players[user_index]
		_play(m, user, _ability(ability_id), m.rivals[aim])
		m.turn_taken.connect(
			func(who, action, _lines):
				var i: int = m.rivals.find(who)
				if i < 0:
					return
				if action.kind == TALK:
					out["talk"][i] += 1
					if action.targets.has(user):
						out["talk_at_user"][i] += 1
				elif action.kind == MEDITATE:
					out["meditate"][i] += 1
		)
		await m.run(1)
		m.free()
	return out


## Whether a count out of `runs` is near `p` * `runs`: within four standard deviations.
func _near(count: int, p: float, runs: int) -> bool:
	var sd := sqrt(runs * p * (1.0 - p))
	return absf(count - p * runs) <= 4.0 * sd


func _step() -> float:
	return BalanceData.current().action_weight_bonus


## After two rounds, how many weights each individual still holds. The user's next turn is the
## start of round 2.
func _weights_after_two_rounds(
	player_ids: Array, rival_ids: Array, user_index: int, ability_id: StringName
) -> Array:
	var m := _encounter(player_ids, rival_ids, 77)
	var user: EncounterIndividual = m.players[user_index]
	_play(m, user, _ability(ability_id), m.rivals[0])
	await m.run(2)
	# The rivals' side only: a rival's own Hyping Up or Radiant Secret weighs the players.
	var held: Array = []
	for f in m.rivals:
		held.append(f.action_weights.size())
	m.free()
	return held


# --------------------------------------------------------------------------
# The five abilities
# --------------------------------------------------------------------------


func _check_radiant_secret() -> void:
	print("[radiant secret]")
	var runs := 300
	var duo := [&"fliritus", &"kalilk"]
	var foes := [&"ravbak", &"skorpis"]
	var s := await _sample(duo, foes, 0, &"radiant_secret", 0, runs)
	_check(
		_near(s["talk"][0], _step(), runs),
		"the targeted rival Talks by the step (%d)" % s["talk"][0]
	)
	_check(s["talk"][1] == 0, "the other rival does not Talk")
	_check(s["meditate"][0] == 0 and s["meditate"][1] == 0, "nobody Meditates")
	var held := await _weights_after_two_rounds(duo, foes, 0, &"radiant_secret")
	_check(held == [0, 0], "it runs out at the user's next turn (%s)" % [held])


func _check_hyping_up() -> void:
	print("[hyping up]")
	var runs := 300
	var duo := [&"ravbak", &"kalilk"]
	var foes := [&"skorpis", &"akturlin"]
	var s := await _sample(duo, foes, 0, &"hyping_up", 0, runs)
	_check(_near(s["talk"][0], _step(), runs), "one rival Talks by the step (%d)" % s["talk"][0])
	_check(_near(s["talk"][1], _step(), runs), "...and so does the other (%d)" % s["talk"][1])
	var held := await _weights_after_two_rounds(duo, foes, 0, &"hyping_up")
	_check(held == [0, 0], "it runs out at the user's next turn (%s)" % [held])
	var m := _encounter(duo, foes, 5)
	_play(m, m.players[0], _ability(&"hyping_up"), m.rivals[0])
	# Looked at when the teammate's turn comes, before any rival has acted.
	var seen := [-1, -1]
	(m.agent_for(m.players[1]) as Player).spy = func():
		seen[0] = m.rivals[0].action_weights.size()
		seen[1] = m.players[0].action_weights.size()
	await m.run(1)
	_check(seen[0] == 1, "the rivals are weighed as soon as it is used")
	_check(seen[1] == 0, "the user's side gets no weight")
	m.free()


func _check_misty_secret() -> void:
	print("[misty secret]")
	var runs := 300
	var duo := [&"vilgane", &"kalilk"]
	var foes := [&"ravbak", &"skorpis"]
	var s := await _sample(duo, foes, 0, &"misty_secret", 0, runs)
	_check(
		_near(s["meditate"][0], _step(), runs),
		"a rival Meditates by the step (%d)" % s["meditate"][0]
	)
	_check(
		_near(s["meditate"][1], _step(), runs), "...and so does the other (%d)" % s["meditate"][1]
	)
	_check(s["talk"][0] == 0 and s["talk"][1] == 0, "nobody Talks")
	# Using objects is weighted, but rivals carry none yet: the weight is held all the same.
	var m := _encounter(duo, foes, 5)
	_play(m, m.players[0], _ability(&"misty_secret"), m.rivals[0])
	await m.run(1)
	var object := EncounterAction.Kind.USE_OBJECT
	_check(m.rivals[0].action_bonus(object) == _step(), "objects are weighted too")
	_check(m.players[1].action_bonus(object) == 0.0, "...for rivals only")
	m.free()
	var held := await _weights_after_two_rounds(duo, foes, 0, &"misty_secret")
	_check(held == [0, 0], "it runs out at the user's next turn (%s)" % [held])


func _check_ones_ethos() -> void:
	print("[one's ethos]")
	# akturlin and ravbak share an origin; vilgane does not.
	var runs := 1000
	var duo := [&"akturlin", &"kalilk"]
	var foes := [&"ravbak", &"vilgane"]
	var s := await _sample(duo, foes, 0, &"one_s_ethos", 0, runs)
	var step := BalanceData.current().ethos_talk_bonus
	_check(step == 0.05, "the doc's 5 %")
	_check(
		_near(s["talk"][0], step, runs),
		"a rival of the user's origin Talks 5 %% more (%d of %d)" % [s["talk"][0], runs]
	)
	_check(s["talk"][0] > 0, "...and does Talk")
	_check(s["talk"][1] == 0, "a rival of another origin does not")
	var held := await _weights_after_two_rounds(duo, foes, 0, &"one_s_ethos")
	_check(held == [1, 0], "it holds for the rest of the encounter (%s)" % [held])


func _check_business_card() -> void:
	print("[business card]")
	# hibulus and fliritus share an origin; ravbak does not. The user is the SECOND player, so that
	# a Talk "to it" is not merely the first target.
	var runs := 300
	var duo := [&"kalilk", &"hibulus"]
	var foes := [&"fliritus", &"ravbak"]
	var s := await _sample(duo, foes, 1, &"business_card", 0, runs)
	_check(
		_near(s["talk"][0], _step(), runs),
		"a rival of the user's origin Talks by the step (%d)" % s["talk"][0]
	)
	_check(s["talk"][0] == s["talk_at_user"][0], "...and always to the user")
	_check(s["talk"][1] == 0, "a rival of another origin does not")
	var held := await _weights_after_two_rounds(duo, foes, 1, &"business_card")
	_check(held == [0, 0], "it runs out at the user's next turn (%s)" % [held])


# --------------------------------------------------------------------------
# Replays
# --------------------------------------------------------------------------


func _check_no_weight_no_draw() -> void:
	print("[no weight, no draw]")
	var m := _encounter([&"kalilk", &"fliritus"], [&"ravbak", &"skorpis"], 3)
	var before := m.rng.state
	var agent := AutoAgent.new()
	agent.decide(m.rivals[0], m)
	_check(m.rng.state == before, "an individual with no weight consumes no random number")
	m.rivals[0].add_action_weight(MEDITATE, 0.5)
	agent.decide(m.rivals[0], m)
	_check(m.rng.state != before, "...and one with a weight consumes one")
	m.free()


func _check_same_seed_same_choices() -> void:
	print("[determinism]")
	var logs: Array = []
	for i in 2:
		var m := _encounter([&"hibulus", &"kalilk"], [&"fliritus", &"ravbak"], 99)
		_play(m, m.players[0], _ability(&"business_card"), m.players[0])
		await m.run(3)
		logs.append(m.encounter_log)
		m.free()
	_check(logs[0] == logs[1] and not logs[0].is_empty(), "same seed, same choices and log")
