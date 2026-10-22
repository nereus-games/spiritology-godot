## Headless check of the abilities that REACT to what another individual does: a window opens
## when the ability is used and lasts until its user's next turn, and during it something else's
## Talk, Meditate, targeting or damage sets the effect off. Victimism, Dodge Blur, Unavailability,
## Unfocused Complaint, Business Card, Effort of Neutrality and Homeostasis — each one played
## through a real round, with someone it must touch and someone it must leave alone.
##
## Run with: Godot --headless --path . res://scenes/dev/reactions_check.tscn
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
	await _check_victimism()
	await _check_dodge_blur()
	await _check_unavailability()
	await _check_unfocused_complaint()
	await _check_business_card()
	await _check_effort_of_neutrality()
	await _check_homeostasis()
	await _check_reactions_do_not_chain()
	await _check_lines_reach_the_log()
	print("")
	if _fails.is_empty():
		print("ALL OK")
	else:
		print("FAILURES: %s" % [_fails])
	get_tree().quit(0 if _fails.is_empty() else 1)


# --------------------------------------------------------------------------
# Scaffolding
# --------------------------------------------------------------------------


## Two players and two rivals, in a known order [p0, p1, r0, r1] unless `order` says otherwise
## (as indices into that list). Everyone passes until told otherwise. The caller frees it.
func _encounter(order: Array = [0, 1, 2, 3]) -> EncounterManager:
	var all: Array = []
	for id in [&"kalilk", &"fliritus"]:
		all.append(EncounterManager.make_individual(id, true))
	for id in [&"ravbak", &"skorpis"]:
		all.append(EncounterManager.make_individual(id, false))
	var m := EncounterManager.new()
	m.setup([all[0], all[1]], [all[2], all[3]], 20261022)
	var ordered: Array = []
	for i in order:
		ordered.append(all[i])
	m.timeline.order = ordered
	for f in all:
		m.set_agent(f, Player.new())
	return m


func _play(m: EncounterManager, who: EncounterIndividual, actions: Array) -> void:
	(m.agent_for(who) as Player).queued = actions


func _ability(id: StringName) -> AbilityData:
	return load(ABILITY_DIR + "%s.tres" % id)


## A plain attack with no script of its own: the generic damage effect, ten before modifiers.
func _hit() -> AbilityData:
	var a := AbilityData.new()
	a.id = &"test_hit"
	a.energy = GameEnums.Energy.HEAT
	a.base_damage = 10
	a.tags = PackedStringArray(["damage"])
	return a


func _use(ability: AbilityData, target: EncounterIndividual) -> EncounterAction:
	return EncounterAction.use_ability(ability, [target])


func _talk(target: EncounterIndividual) -> EncounterAction:
	return EncounterAction.of_kind(EncounterAction.Kind.TALK, [target])


func _small() -> int:
	return BalanceData.current().damage(&"small")


# --------------------------------------------------------------------------
# Talk: Victimism, Dodge Blur
# --------------------------------------------------------------------------


func _check_victimism() -> void:
	print("[victimism]")
	var m := _encounter()
	var p0: EncounterIndividual = m.players[0]
	var p1: EncounterIndividual = m.players[1]
	var r0: EncounterIndividual = m.rivals[0]
	var r1: EncounterIndividual = m.rivals[1]
	_play(m, p0, [_use(_ability(&"victimism"), p0)])
	_play(m, p1, [_talk(r1)])
	_play(m, r0, [_talk(p0), _talk(p0)])
	var seen := {}
	(m.agent_for(r0) as Player).spy = func(f, mgr): seen[mgr.round_number] = f.den
	var before := [p1.den, r0.den, r1.den]
	await m.run(2)
	_check(r0.den < before[1], "a rival that Talks takes damage")
	_check(seen.get(2) == r0.den, "...once: its Talk after the user's next turn costs it nothing")
	_check(p1.den == before[0], "a teammate that Talks does not")
	_check(r1.den == before[2], "a rival that does not Talk does not")
	m.free()


func _check_dodge_blur() -> void:
	print("[dodge blur]")
	var m := _encounter()
	var p0: EncounterIndividual = m.players[0]
	var r0: EncounterIndividual = m.rivals[0]
	var r1: EncounterIndividual = m.rivals[1]
	_play(m, p0, [_use(_ability(&"dodge_blur"), p0)])
	_play(m, r0, [_talk(p0)])
	var before := [r0.den, r1.den]
	await m.run(1)
	_check(r0.den < before[0], "a rival that Talks takes damage")
	_check(r1.den == before[1], "a rival that does not Talk does not")
	m.free()


# --------------------------------------------------------------------------
# Being targeted: Unavailability
# --------------------------------------------------------------------------


func _check_unavailability() -> void:
	print("[unavailability]")
	var drain := EthLossEffect.DEFAULT_AMOUNT
	var m := _encounter()
	var p0: EncounterIndividual = m.players[0]
	var p1: EncounterIndividual = m.players[1]
	var r0: EncounterIndividual = m.rivals[0]
	var r1: EncounterIndividual = m.rivals[1]
	_play(m, p0, [_use(_ability(&"unavailability"), p0)])
	_play(m, r0, [_talk(p0)])
	_play(m, r1, [_talk(p1)])
	var before := [r0.eth, r1.eth]
	await m.run(1)
	_check(r0.eth == before[0] - drain, "an individual that Talks to the user loses ETH")
	_check(r1.eth == before[1], "...one that targets someone else does not")
	m.free()

	m = _encounter()
	p0 = m.players[0]
	r1 = m.rivals[1]
	_play(m, p0, [_use(_ability(&"unavailability"), p0)])
	_play(m, r1, [_use(_hit(), p0)])
	var eth := r1.eth
	await m.run(1)
	_check(r1.eth == eth - drain, "...and so does one that attacks it")
	m.free()


# --------------------------------------------------------------------------
# Meditate: Unfocused Complaint
# --------------------------------------------------------------------------


func _check_unfocused_complaint() -> void:
	print("[unfocused complaint]")
	var m := _encounter()
	var p0: EncounterIndividual = m.players[0]
	var p1: EncounterIndividual = m.players[1]
	var r0: EncounterIndividual = m.rivals[0]
	var r1: EncounterIndividual = m.rivals[1]
	_play(m, p0, [_use(_ability(&"unfocused_complaint"), p0)])
	_play(m, p1, [EncounterAction.of_kind(EncounterAction.Kind.MEDITATE, [p1])])
	_play(m, r0, [EncounterAction.of_kind(EncounterAction.Kind.MEDITATE, [r0])])
	_play(m, r1, [_talk(p0)])
	var before := {p0: p0.den, p1: p1.den, r0: r0.den, r1: r1.den}
	await m.run(1)
	_check(r0.den < before[r0] and r0.eth == r0.max_eth - _small(), "a rival that Meditates pays")
	_check(p1.den < before[p1], "...and so does a teammate")
	_check(r1.den == before[r1] and r1.eth == r1.max_eth, "one that does something else does not")
	_check(p0.den == before[p0], "the user is not among those it hurts")
	m.free()


# --------------------------------------------------------------------------
# Being spoken to: Business Card
# --------------------------------------------------------------------------


func _check_business_card() -> void:
	print("[business card]")
	var m := _encounter()
	var p0: EncounterIndividual = m.players[0]
	var p1: EncounterIndividual = m.players[1]
	var r0: EncounterIndividual = m.rivals[0]
	var r1: EncounterIndividual = m.rivals[1]
	p0.den = 50
	p1.den = 50
	_play(m, p0, [_use(_ability(&"business_card"), p0)])
	_play(m, r0, [_talk(p0)])
	_play(m, r1, [_talk(p1)])
	await m.run(1)
	_check(
		p0.den == 50 + 2 * _small(), "the card's DEN, and the same again for each rival that Talks"
	)
	_check(p1.den == 50, "a Talk aimed at someone else gives the user nothing")
	m.free()


# --------------------------------------------------------------------------
# What a teammate's action did: Effort of Neutrality
# --------------------------------------------------------------------------


func _check_effort_of_neutrality() -> void:
	print("[effort of neutrality]")
	for attack in [false, true]:
		var m := _encounter([1, 0, 2, 3])
		var p0: EncounterIndividual = m.players[0]
		var p1: EncounterIndividual = m.players[1]
		var r0: EncounterIndividual = m.rivals[0]
		_play(m, p1, [_use(_ability(&"effort_of_neutrality"), p1)])
		_play(
			m,
			p0,
			(
				[_use(_hit(), r0)]
				if attack
				else [EncounterAction.of_kind(EncounterAction.Kind.MEDITATE, [p0])]
			)
		)
		var weakness := {}
		(m.agent_for(p0) as Player).spy = func(f, mgr):
			weakness["p0_turn"] = f.active_weakness(mgr.timeline.position_of(f))
		(m.agent_for(r0) as Player).spy = func(f, mgr):
			weakness["r0_turn"] = p0.active_weakness(mgr.timeline.position_of(p0))
		await m.run(1)
		var own := p0.species.weakness_for(m.timeline.position_of(p0))
		var none := GameEnums.Energy.NONE
		_check(own != none, "[%s] the teammate has a weakness of its own to lose" % attack)
		_check(weakness.get("p0_turn") == own, "[%s] it keeps it until it has acted" % attack)
		if attack:
			_check(weakness.get("r0_turn") == own, "an action that deals damage costs it nothing")
		else:
			_check(
				weakness.get("r0_turn") == none, "an action that deals none loses it the weakness"
			)
		_check(
			p1.active_weakness(m.timeline.position_of(p1)) == none,
			"[%s] the user has none either" % attack
		)
		m.free()


# --------------------------------------------------------------------------
# Being damaged: Homeostasis
# --------------------------------------------------------------------------


func _check_homeostasis() -> void:
	print("[homeostasis]")
	var m := _encounter()
	var p0: EncounterIndividual = m.players[0]
	var r0: EncounterIndividual = m.rivals[0]
	var r1: EncounterIndividual = m.rivals[1]
	p0.eth = 0
	_play(m, p0, [_use(_ability(&"homeostasis"), p0)])
	_play(m, r0, [_use(_hit(), p0), _use(_hit(), p0)])
	_play(m, r1, [_use(_hit(), p0)])
	var seen := {}
	(m.agent_for(r0) as Player).spy = func(f, mgr): seen[mgr.round_number] = p0.eth
	var p1: EncounterIndividual = m.players[1]
	var p1_eth := p1.eth
	await m.run(2)
	_check(seen.get(1) == 0, "using it gains nothing by itself")
	_check(seen.get(2) == 2 * _small(), "ETH comes with each hit: two hits, twice the ETH")
	_check(p0.eth == 2 * _small(), "...and a hit after the user's next turn brings none")
	_check(p1.eth == p1_eth, "a teammate is not covered")
	m.free()


# --------------------------------------------------------------------------
# What the player is told
# --------------------------------------------------------------------------


func _check_lines_reach_the_log() -> void:
	print("[the log]")
	var m := _encounter()
	var p0: EncounterIndividual = m.players[0]
	var r0: EncounterIndividual = m.rivals[0]
	_play(m, p0, [_use(_ability(&"victimism"), p0)])
	_play(m, r0, [_talk(p0)])
	var heard: Array = []
	m.reaction_noted.connect(
		func(owner, ability, lines): heard.append([owner, ability.id, lines.size()])
	)
	await m.run(1)
	_check(heard.size() == 1, "one reaction announced (%d)" % heard.size())
	if heard.size() == 1:
		_check(
			heard[0][0] == p0 and heard[0][1] == &"victimism", "...as the owner's and the ability's"
		)
		_check(heard[0][2] >= 1, "...with what it did")
	m.free()


func _check_reactions_do_not_chain() -> void:
	print("[chaining]")
	var m := _encounter()
	var p0: EncounterIndividual = m.players[0]
	var r0: EncounterIndividual = m.rivals[0]
	# No ability of the seven can put its owner in two windows at once, so the second one is armed
	# by hand: Homeostasis on the rival that is about to Talk, held until the other rival's turn,
	# which comes after its own.
	r0.watch(_ability(&"homeostasis"), m.rivals[1])
	r0.eth = 0
	_play(m, p0, [_use(_ability(&"victimism"), p0)])
	_play(m, r0, [_talk(p0)])
	var before := r0.den
	await m.run(1)
	_check(r0.den < before, "the rival is punished for Talking")
	_check(r0.eth == 0, "...and that damage does not set off its own reaction")
	m.free()
