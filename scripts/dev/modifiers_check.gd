## Headless check of the next-turn modifiers: what an ability does to its user's (or its
## teammates') NEXT action — the ability that costs nothing (Self-Forgiveness), the Talk that
## yields as much as an Examine (Active Listening), damage a tier higher (Priming) and a Talk
## that yields less (Hardening). Each one is played through real rounds with someone it must
## touch and someone it must leave alone, and shown to run out across the round boundary.
##
## Run with: Godot --headless --path . res://scenes/dev/modifiers_check.tscn
## As a start scene rather than --script; see geometry_check.gd.
extends Node

const ABILITY_DIR := "res://data/abilities/"

var _fails: Array[String] = []


## Plays queued actions, then passes. `spy`, when set, is told each time the individual is asked,
## which is how a check looks at the state as a turn begins.
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
	await _check_self_forgiveness()
	await _check_active_listening()
	await _check_priming()
	_check_tier_step()
	await _check_hardening()
	print("")
	if _fails.is_empty():
		print("ALL OK")
	else:
		print("FAILURES: %s" % [_fails])
	get_tree().quit(0 if _fails.is_empty() else 1)


# --------------------------------------------------------------------------
# Scaffolding
# --------------------------------------------------------------------------


## Two players and two rivals, in the order [p0, p1, r0, r1]. Everyone passes until told
## otherwise. The caller frees it.
func _encounter() -> EncounterManager:
	var all: Array = []
	for id in [&"kalilk", &"fliritus"]:
		all.append(EncounterManager.make_individual(id, true))
	for id in [&"ravbak", &"skorpis"]:
		all.append(EncounterManager.make_individual(id, false))
	var m := EncounterManager.new()
	m.setup([all[0], all[1]], [all[2], all[3]], 20261022)
	m.timeline.order = all.duplicate()
	for f in all:
		m.set_agent(f, Player.new())
	return m


func _play(m: EncounterManager, who: EncounterIndividual, actions: Array) -> void:
	(m.agent_for(who) as Player).queued = actions


func _spy(m: EncounterManager, who: EncounterIndividual, spy: Callable) -> void:
	(m.agent_for(who) as Player).spy = spy


func _ability(id: StringName) -> AbilityData:
	return load(ABILITY_DIR + "%s.tres" % id)


## A plain attack with no script of its own: the generic damage effect, ten before modifiers,
## at a real ETH cost.
func _hit() -> AbilityData:
	var a := AbilityData.new()
	a.id = &"test_hit"
	a.energy = GameEnums.Energy.HEAT
	a.cost = GameEnums.Cost.NORMAL
	a.base_damage = 10
	a.tags = PackedStringArray(["damage"])
	return a


func _use(ability: AbilityData, target: EncounterIndividual) -> EncounterAction:
	return EncounterAction.use_ability(ability, [target])


func _talk(target: EncounterIndividual) -> EncounterAction:
	return EncounterAction.of_kind(EncounterAction.Kind.TALK, [target])


func _pass(who: EncounterIndividual) -> EncounterAction:
	return EncounterAction.of_kind(EncounterAction.Kind.PASS, [who])


## Makes every Talk to the rivals work (1.0) or fail (0.0); returns what to restore.
func _force_dialogue(m: EncounterManager, chance: float) -> Array:
	var saved: Array = []
	for r in m.rivals:
		saved.append([r.species, r.species.talker_chance])
		r.species.talker_chance = chance
	return saved


func _restore_dialogue(saved: Array) -> void:
	for entry in saved:
		entry[0].talker_chance = entry[1]


## Records every IFP award as [action, factor] in the order they are announced.
func _record_ifp(m: EncounterManager) -> Array:
	var seen: Array = []
	m.ifp_earned.connect(
		func(_species, action, _forlorn, _effective, factor): seen.append([action, factor])
	)
	return seen


# --------------------------------------------------------------------------
# Self-Forgiveness: the next ability is free
# --------------------------------------------------------------------------


func _check_self_forgiveness() -> void:
	print("[self-forgiveness]")
	var cost := _hit().eth_cost()
	_check(cost > 0, "the test attack costs ETH (%d)" % cost)

	# Round 1: p0 forgives itself, p1 attacks. Round 2: both attack, p0 with an empty reserve.
	var m := _encounter()
	var p0: EncounterIndividual = m.players[0]
	var p1: EncounterIndividual = m.players[1]
	var r1: EncounterIndividual = m.rivals[1]
	_play(m, p0, [_use(_ability(&"self_forgiveness"), p0), _use(_hit(), r1)])
	_play(m, p1, [_use(_hit(), r1), _use(_hit(), r1)])
	var afford := {}
	var p1_eth := {}
	_spy(
		m,
		p0,
		func(f, mgr):
			if mgr.round_number == 2:
				f.eth = 0
				afford["free"] = f.can_afford(_hit())
	)
	_spy(m, p1, func(f, mgr): p1_eth[mgr.round_number] = f.eth)
	await m.run(2)
	_check(afford.get("free", false), "an empty individual can afford the ability that is free")
	_check(p0.eth == 0, "the user pays nothing for its next ability (ETH %d)" % p0.eth)
	_check(r1.den < r1.max_den, "...and the ability does take effect")
	_check(p1_eth[2] == p1.max_eth - cost, "a teammate paid for its own attack")
	_check(p1.eth == p1_eth[2] - cost, "...each time")
	m.free()

	# Spent: two abilities in a row, only the first is free.
	m = _encounter()
	p0 = m.players[0]
	r1 = m.rivals[1]
	_play(m, p0, [_use(_ability(&"self_forgiveness"), p0), _use(_hit(), r1), _use(_hit(), r1)])
	var eth := {}
	_spy(m, p0, func(f, mgr): eth[mgr.round_number] = f.eth)
	await m.run(3)
	_check(eth[2] == eth[3], "the first ability of the next turn is free")
	_check(p0.eth == eth[3] - cost, "...the following one is not")
	m.free()

	# Expired: not used on the next turn, so gone by the turn after.
	m = _encounter()
	p0 = m.players[0]
	r1 = m.rivals[1]
	_play(m, p0, [_use(_ability(&"self_forgiveness"), p0), _pass(p0), _use(_hit(), r1)])
	eth = {}
	_spy(m, p0, func(f, mgr): eth[mgr.round_number] = f.eth)
	await m.run(3)
	_check(not p0.free_next_ability, "unused, the free ability is gone")
	_check(p0.eth == eth[3] - cost, "...so an ability two turns later is paid for")
	m.free()


# --------------------------------------------------------------------------
# Active Listening: the next Talk yields as much as an Examine
# --------------------------------------------------------------------------


func _check_active_listening() -> void:
	print("[active listening]")
	var examine := GameEnums.IfpAction.EXAMINE_RIVAL
	var talk := GameEnums.IfpAction.TALK_RIVAL

	var m := _encounter()
	var saved := _force_dialogue(m, 1.0)
	var p0: EncounterIndividual = m.players[0]
	var p1: EncounterIndividual = m.players[1]
	var r0: EncounterIndividual = m.rivals[0]
	_play(m, p0, [_use(_ability(&"active_listening"), p0), _talk(r0), _talk(r0)])
	_play(m, p1, [_talk(r0), _talk(r0)])
	var seen := _record_ifp(m)
	await m.run(3)
	# Announced in turn order: p1 in round 1, then p0 and p1 in round 2, then p0 in round 3.
	_check(seen.size() == 4, "four Talks were awarded (%d)" % seen.size())
	if seen.size() == 4:
		_check(seen[0][0] == talk, "a teammate's Talk right after the cast is an ordinary one")
		_check(seen[1][0] == examine, "the user's next Talk yields as an Examine")
		_check(seen[2][0] == talk, "a teammate's Talk the same round does not")
		_check(seen[3][0] == talk, "the Talk after that is an ordinary one: it was spent")
	_restore_dialogue(saved)
	m.free()

	# An ineffective Talk keeps earning nothing, though it spends the bonus.
	m = _encounter()
	saved = _force_dialogue(m, 0.0)
	p0 = m.players[0]
	r0 = m.rivals[0]
	_play(m, p0, [_use(_ability(&"active_listening"), p0), _talk(r0), _talk(r0)])
	seen = _record_ifp(m)
	await m.run(3)
	_check(seen.size() == 2 and seen[0][0] == talk, "an ineffective Talk is not upgraded")
	_check(not p0.talk_as_examine, "...and still spends the bonus")
	_restore_dialogue(saved)
	m.free()

	# Expired: no Talk on the next turn, so none counts as an Examine on the one after.
	m = _encounter()
	saved = _force_dialogue(m, 1.0)
	p0 = m.players[0]
	r0 = m.rivals[0]
	_play(m, p0, [_use(_ability(&"active_listening"), p0), _pass(p0), _talk(r0)])
	seen = _record_ifp(m)
	await m.run(3)
	_check(seen.size() == 1 and seen[0][0] == talk, "a Talk two turns later is ordinary")
	_check(not p0.talk_as_examine, "...the bonus having run out")
	_restore_dialogue(saved)
	m.free()


# --------------------------------------------------------------------------
# Priming: the teammates' damage steps up one tier
# --------------------------------------------------------------------------


## One encounter, primed or not, in which p1 hits r0 every round, p0 hits r1 in round 2 and r0
## hits p0 in round 1. Returns the damage of each, by label.
func _priming_run(primed: bool) -> Dictionary:
	var m := _encounter()
	var p0: EncounterIndividual = m.players[0]
	var p1: EncounterIndividual = m.players[1]
	var r0: EncounterIndividual = m.rivals[0]
	var r1: EncounterIndividual = m.rivals[1]
	var first := _use(_ability(&"priming"), p0) if primed else _pass(p0)
	_play(m, p0, [first, _use(_hit(), r1)])
	_play(m, p1, [_use(_hit(), r0), _use(_hit(), r0), _use(_hit(), r0)])
	_play(m, r0, [_use(_hit(), p0)])
	var dealt := {}
	var last := {"r0": r0.den, "p0": p0.den, "r1": r1.den}
	m.turn_taken.connect(
		func(who, _action, _lines):
			if who == p1:
				dealt["p1:%d" % m.round_number] = last["r0"] - r0.den
				last["r0"] = r0.den
			elif who == p0 and m.round_number == 2:
				dealt["p0:2"] = last["r1"] - r1.den
				last["r1"] = r1.den
			elif who == r0 and m.round_number == 1:
				dealt["r0:1"] = last["p0"] - p0.den
	)
	await m.run(3)
	m.free()
	return dealt


func _check_priming() -> void:
	print("[priming]")
	var base := await _priming_run(false)
	var primed := await _priming_run(true)
	_check(
		primed["p1:1"] > base["p1:1"],
		"a teammate hits harder (%d vs %d)" % [primed["p1:1"], base["p1:1"]]
	)
	_check(primed["p0:2"] == base["p0:2"], "...the user itself does not")
	_check(primed["r0:1"] == base["r0:1"], "...nor does a rival")
	# p1 is moved to the front for round 2, before the user's turn comes round again.
	_check(primed["p1:2"] > base["p1:2"], "...for as long as the user's next turn has not begun")
	_check(primed["p1:3"] == base["p1:3"], "...and no longer after")


func _check_tier_step() -> void:
	print("[damage tiers]")
	var b := BalanceData.current()
	_check(b.step_up_damage(b.damage_mini) == b.damage_small, "mini steps up to small")
	_check(b.step_up_damage(b.damage_small) == b.damage_normal, "small steps up to normal")
	_check(b.step_up_damage(b.damage_normal) == b.damage_big, "normal steps up to big")
	_check(b.step_up_damage(b.damage_big) == b.damage_big, "big stays big")
	_check(
		b.step_up_damage(b.damage_small + 1) == b.damage_normal, "between tiers goes up to the next"
	)


# --------------------------------------------------------------------------
# Hardening: the Talk yields less
# --------------------------------------------------------------------------


func _check_hardening() -> void:
	print("[hardening]")
	var factor := 1.0 - BalanceData.current().hardening_talk_penalty
	var m := _encounter()
	var saved := _force_dialogue(m, 1.0)
	var p0: EncounterIndividual = m.players[0]
	var p1: EncounterIndividual = m.players[1]
	var r0: EncounterIndividual = m.rivals[0]
	_play(m, p0, [_use(_ability(&"hardening"), p0), _talk(r0), _talk(r0)])
	_play(m, p1, [_pass(p1), _talk(r0)])
	var seen := _record_ifp(m)
	await m.run(3)
	# Announced in turn order: round 2 p0 then p1, round 3 p0.
	_check(seen.size() == 3, "three Talks were awarded (%d)" % seen.size())
	if seen.size() == 3:
		_check(is_equal_approx(seen[0][1], factor), "the hardened individual's Talk yields less")
		_check(is_equal_approx(seen[1][1], 1.0), "a teammate's Talk is untouched")
		_check(is_equal_approx(seen[2][1], 1.0), "...and the hardened one's, once it has run out")
	_check(is_equal_approx(p0.talk_info_factor, 1.0), "the factor is back to 1 afterwards")
	_restore_dialogue(saved)
	m.free()
