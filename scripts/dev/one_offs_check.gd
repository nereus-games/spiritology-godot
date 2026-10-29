## Headless check of four abilities that stand alone: Shuffle (trade ETH according to the new
## positions), Deflection (the damage matching a weakness is doubled for everyone), Self-Denial
## (a drain at the start of each of the rival's turns, until it Meditates) and Tactical Retreat
## (Arcane damage becomes ETH). Each one is played through real rounds, with someone it must touch
## and someone it must leave alone.
##
## Run with: Godot --headless --path . res://scenes/dev/one_offs_check.tscn
## As a start scene rather than --script; see geometry_check.gd.
extends Node

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
	_check_shuffle()
	await _check_deflection()
	await _check_self_denial()
	await _check_tactical_retreat()
	print("")
	if _fails.is_empty():
		print("ALL OK")
	else:
		print("FAILURES: %s" % [_fails])
	get_tree().quit(0 if _fails.is_empty() else 1)


# --------------------------------------------------------------------------
# Scaffolding
# --------------------------------------------------------------------------


## Two players and two rivals in the order [p0, p1, r0, r1]. Everyone passes until told otherwise.
## The caller frees it.
func _encounter(seed: int = 20261022) -> EncounterManager:
	var all: Array = []
	for id in [&"kalilk", &"fliritus"]:
		all.append(EncounterManager.make_individual(id, true))
	for id in [&"ravbak", &"skorpis"]:
		all.append(EncounterManager.make_individual(id, false))
	var m := EncounterManager.new()
	m.setup([all[0], all[1]], [all[2], all[3]], seed)
	m.timeline.order = all.duplicate()
	for f in all:
		m.set_agent(f, Player.new())
	return m


func _play(m: EncounterManager, who: EncounterIndividual, actions: Array) -> void:
	(m.agent_for(who) as Player).queued = actions


func _ability(id: StringName) -> AbilityData:
	return load(ABILITY_DIR + "%s.tres" % id)


## A plain attack with no script of its own: the generic damage effect, ten before modifiers.
func _hit(energy: GameEnums.Energy) -> AbilityData:
	var a := AbilityData.new()
	a.id = &"test_hit"
	a.energy = energy
	a.base_damage = 10
	a.tags = PackedStringArray(["damage"])
	return a


func _use(ability: AbilityData, target: EncounterIndividual) -> EncounterAction:
	return EncounterAction.use_ability(ability, [target])


func _meditate(who: EncounterIndividual) -> EncounterAction:
	return EncounterAction.of_kind(EncounterAction.Kind.MEDITATE, [who])


func _pass(who: EncounterIndividual) -> EncounterAction:
	return EncounterAction.of_kind(EncounterAction.Kind.PASS, [who])


func _no_weakness(who: EncounterIndividual) -> void:
	who.override_weakness(GameEnums.Energy.NONE, null, EncounterIndividual.FOR_ENCOUNTER)


func _weak_to(who: EncounterIndividual, energy: GameEnums.Energy) -> void:
	who.override_weakness(energy, null, EncounterIndividual.FOR_ENCOUNTER)


## What one hit costs `target` in DEN given the weakness it exposes (`weak_to`, NONE for none),
## measured in a round of its own so that no rule under test can leak into the figure.
func _hit_cost(
	attacker: int, energy: GameEnums.Energy, target: int, weak_to := GameEnums.Energy.NONE
) -> int:
	var m := _encounter()
	var all: Array = m.players + m.rivals
	_weak_to(all[target], weak_to)
	_play(m, all[attacker], [_use(_hit(energy), all[target])])
	var before: int = all[target].den
	await m.run(1)
	var cost: int = before - all[target].den
	m.free()
	return cost


# --------------------------------------------------------------------------
# Shuffle
# --------------------------------------------------------------------------


## Everyone's ETH after a Shuffle by p0 on four individuals of whom the last is dissolved, and the
## order of those standing afterwards. p0 is weak to Heat; nobody else is weak.
func _shuffle_case(seed: int) -> Dictionary:
	var m := _encounter(seed)
	var all: Array = m.players + m.rivals
	var start := [11, 22, 33, 44]
	for i in 4:
		all[i].eth = start[i]
		_no_weakness(all[i])
	_weak_to(all[0], GameEnums.Energy.HEAT)
	all[3].den = 0
	var ctx := m._make_context(all[0], _ability(&"shuffle"), [all[0]])
	EffectCatalog.script_for(ctx.ability).execute(ctx)
	m.timeline.apply_pending()
	var out := {"all": all, "start": start, "order": m.timeline.living(), "max": all[0].max_eth}
	out["eth"] = [all[0].eth, all[1].eth, all[2].eth, all[3].eth]
	m.free()
	return out


func _check_shuffle() -> void:
	print("[shuffle]")
	var c := {}
	for seed in 40:
		c = _shuffle_case(20261022 + seed)
		var all: Array = c["all"]
		if c["order"] != [all[0], all[1], all[2]]:
			break
	var all: Array = c["all"]
	var order: Array = c["order"]
	var eth: Array = c["eth"]
	var start: Array = c["start"]
	_check(order != [all[0], all[1], all[2]], "the order of those standing did move")
	var ok := true
	for i in order.size():
		# Whoever stands at place i now holds what the one standing there before held, the
		# Heat-weak one excepted: it is refilled afterwards.
		var who: EncounterIndividual = order[i]
		var want: int = c["max"] if who == all[0] else start[i]
		if eth[all.find(who)] != want:
			ok = false
	_check(ok, "each living individual holds the ETH of whoever stood at its new place")
	_check(eth[3] == start[3], "a dissolved individual neither gives nor takes ETH")
	_check(eth[0] == c["max"], "whoever exposes Heat is refilled once the trade is made")


# --------------------------------------------------------------------------
# Deflection
# --------------------------------------------------------------------------


func _check_deflection() -> void:
	print("[deflection]")
	var heat := GameEnums.Energy.HEAT
	var on_weakness := await _hit_cost(2, heat, 1, heat)
	var off_weakness := await _hit_cost(3, heat, 0, GameEnums.Energy.ARCANE)
	var m := _encounter()
	var p0: EncounterIndividual = m.players[0]
	var p1: EncounterIndividual = m.players[1]
	var r0: EncounterIndividual = m.rivals[0]
	var r1: EncounterIndividual = m.rivals[1]
	# p1 is weak to Heat and p0 to Arcane, for good; every hit is Heat.
	_weak_to(p1, heat)
	_weak_to(p0, GameEnums.Energy.ARCANE)
	_play(m, p0, [_use(_ability(&"deflection"), r0)])
	_play(m, r0, [_use(_hit(heat), p1), _use(_hit(heat), p1)])
	_play(m, r1, [_use(_hit(heat), p0)])
	var after_r0: Array = []
	m.turn_taken.connect(
		func(who, _action, _lines):
			if who == r0:
				after_r0.append(p1.den)
	)
	await m.run(2)
	var first: int = 100 - after_r0[0]
	var second: int = after_r0[0] - after_r0[1]
	_check(
		first == 2 * on_weakness, "damage on a weakness is doubled (%d, %d)" % [first, on_weakness]
	)
	_check(100 - p0.den == off_weakness, "...damage that matches no weakness is not")
	_check(second == on_weakness, "...and the doubling ends with the user's next turn")
	m.free()
	await _check_deflection_condition()


## "Requires that the user has not used the same action twice": read from the history.
func _check_deflection_condition() -> void:
	var deflection := _ability(&"deflection")
	var heat := GameEnums.Energy.HEAT
	var m := _encounter()
	var p0: EncounterIndividual = m.players[0]
	var r0: EncounterIndividual = m.rivals[0]
	p0.ability_ids.append(&"deflection")
	_check(m.can_play(p0, deflection), "a fresh user may Deflect")
	_play(m, p0, [_use(_hit(heat), r0)])
	await m.run(1)
	_check(m.can_play(p0, deflection), "...after one action")
	m.free()
	m = _encounter()
	p0 = m.players[0]
	r0 = m.rivals[0]
	p0.ability_ids.append(&"deflection")
	_play(m, p0, [_use(_hit(heat), r0), _use(_hit(heat), r0)])
	await m.run(2)
	_check(not m.can_play(p0, deflection), "...not after the same ability twice in a row")
	_check(not m.usable_abilities(p0).has(deflection), "...and the menu does not offer it")
	# Used regardless, it does nothing.
	var weakness: GameEnums.Energy = r0.active_weakness(m.timeline.position_of(r0))
	var ctx := m._make_context(p0, deflection, [r0])
	EffectCatalog.script_for(deflection).execute(ctx)
	_check(
		r0.active_weakness(m.timeline.position_of(r0)) == weakness,
		"...and used regardless, it changes no weakness"
	)
	m.free()

	# Two different abilities, or an ability between two equal ones, lift the ban.
	m = _encounter()
	p0 = m.players[0]
	r0 = m.rivals[0]
	p0.ability_ids.append(&"deflection")
	_play(m, p0, [_use(_hit(heat), r0), _meditate(p0)])
	await m.run(2)
	_check(m.can_play(p0, deflection), "different actions in a row do not bar it")
	m.free()

	m = _encounter()
	p0 = m.players[0]
	r0 = m.rivals[0]
	p0.ability_ids.append(&"deflection")
	_play(m, p0, [_meditate(p0), _meditate(p0)])
	await m.run(2)
	_check(not m.can_play(p0, deflection), "...two Meditates are the same action as well")
	_play(m, p0, [_pass(p0)])
	await m.run(1)
	_check(m.can_play(p0, deflection), "...and a pass in between is a different one")
	m.free()


# --------------------------------------------------------------------------
# Self-Denial
# --------------------------------------------------------------------------


func _check_self_denial() -> void:
	print("[self-denial]")
	var small := BalanceData.current().damage(&"small")
	var m := _encounter()
	var p0: EncounterIndividual = m.players[0]
	var r0: EncounterIndividual = m.rivals[0]
	var r1: EncounterIndividual = m.rivals[1]
	_play(m, p0, [_use(_ability(&"self_denial"), r0)])
	var heard: Array = []
	m.reaction_noted.connect(func(who, ability, _lines): heard.append([who, ability.id]))
	var eth := r0.eth
	await m.run(3)
	_check(
		r0.eth == eth - small - 3 * small,
		"the rival loses ETH when hit and at the start of each of its turns (%d)" % r0.eth
	)
	_check(r1.eth == r1.max_eth, "...a rival that was not targeted loses none")
	_check(heard.size() == 3 and heard[0] == [r0, &"self_denial"], "...and each drain is announced")
	_check(
		(
			r0.active_weakness(GameEnums.TurnPosition.FIRST)
			== r0.active_weakness(GameEnums.TurnPosition.LAST)
		),
		"...its weaknesses all became one"
	)
	m.free()

	m = _encounter()
	p0 = m.players[0]
	r0 = m.rivals[0]
	_play(m, p0, [_use(_ability(&"self_denial"), r0)])
	_play(m, r0, [_pass(r0), _meditate(r0)])
	eth = r0.eth
	await m.run(3)
	var meditate := BalanceData.current().meditate_eth
	_check(
		r0.eth == eth - small - 2 * small + meditate,
		"Meditating ends the drain: nothing more is lost afterwards (%d)" % r0.eth
	)
	var back := true
	for pos in [
		GameEnums.TurnPosition.FIRST, GameEnums.TurnPosition.MIDDLE, GameEnums.TurnPosition.LAST
	]:
		back = back and r0.active_weakness(pos) == r0.species.weakness_for(pos)
	_check(back, "...and gives back the weaknesses its position implies")
	m.free()


# --------------------------------------------------------------------------
# Tactical Retreat
# --------------------------------------------------------------------------


func _check_tactical_retreat() -> void:
	print("[tactical retreat]")
	var arcane := GameEnums.Energy.ARCANE
	var arcane_on_p0 := await _hit_cost(2, arcane, 0)
	var arcane_on_p1 := await _hit_cost(3, arcane, 1)
	var heat_on_p0 := await _hit_cost(3, GameEnums.Energy.HEAT, 0)
	var m := _encounter()
	var p0: EncounterIndividual = m.players[0]
	var p1: EncounterIndividual = m.players[1]
	var r0: EncounterIndividual = m.rivals[0]
	var r1: EncounterIndividual = m.rivals[1]
	for f in m.players + m.rivals:
		_no_weakness(f)
	var retreat := _ability(&"tactical_retreat")
	p0.eth = 20
	_play(m, p0, [_use(retreat, p0)])
	_play(m, r0, [_use(_hit(arcane), p0), _use(_hit(arcane), p0), _use(_hit(arcane), p0)])
	_play(m, r1, [_use(_hit(arcane), p1), _use(_hit(GameEnums.Energy.HEAT), p0)])
	await m.run(3)
	_check(
		p0.eth == 20 - retreat.eth_cost() + 2 * arcane_on_p0,
		"Arcane damage becomes ETH while it lasts (%d)" % p0.eth
	)
	_check(
		p0.den == 100 - heat_on_p0 - arcane_on_p0,
		"...other energies still cost DEN, and so does Arcane once it has ended (%d)" % p0.den
	)
	_check(p1.den == 100 - arcane_on_p1, "a teammate takes Arcane damage as usual")
	_check(m.timeline.order.back() == p0, "the user still moves last")
	m.free()
