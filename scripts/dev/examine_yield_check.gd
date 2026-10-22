## Headless check of what an Examine yields: the info bonuses of Priming and Catatonia, the
## talent factor of Reconnaissance Glide, how the two multiply, and how GameSession turns the
## factor into whole IFP. Halo Effect's own Examine is covered by `history_check.gd`, where its
## conditions are set up.
##
## Run with: Godot --headless --path . res://scenes/dev/examine_yield_check.tscn
## As a start scene rather than --script; see geometry_check.gd.
extends Node

const Model := preload("res://scripts/encyclopaedia/encyclopaedia_model.gd")
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
	_check_rounding()
	_check_award()
	await _check_plain()
	await _check_catatonia()
	await _check_priming()
	await _check_recon_glide()
	await _check_examine_weakness()
	print("")
	if _fails.is_empty():
		print("ALL OK")
	else:
		print("FAILURES: %s" % [_fails])
	get_tree().quit(0 if _fails.is_empty() else 1)


func _step() -> float:
	return BalanceData.current().examine_bonus_step


func _ability(id: StringName) -> AbilityData:
	return load(ABILITY_DIR + "%s.tres" % id)


func _examine(target: EncounterIndividual) -> EncounterAction:
	return EncounterAction.of_kind(EncounterAction.Kind.EXAMINE, [target])


func _use(id: StringName, target: EncounterIndividual) -> EncounterAction:
	return EncounterAction.use_ability(_ability(id), [target])


func _pass(who: EncounterIndividual) -> EncounterAction:
	return EncounterAction.of_kind(EncounterAction.Kind.PASS, [who])


## Two players and two rivals in the order [p0, p1, r0, r1]; `first` is the species of p0.
## Everyone passes until told otherwise.
func _encounter(first := &"kalilk") -> EncounterManager:
	var all: Array = []
	for id in [first, &"fliritus"]:
		all.append(EncounterManager.make_individual(id, true))
	for id in [&"skorpis", &"skorpis"]:
		all.append(EncounterManager.make_individual(id, false))
	var m := EncounterManager.new()
	m.setup([all[0], all[1]], [all[2], all[3]], 20261022)
	m.timeline.order = all.duplicate()
	for f in all:
		m.set_agent(f, Player.new())
		f.eth = 20
	return m


func _play(m: EncounterManager, who: EncounterIndividual, actions: Array) -> void:
	(m.agent_for(who) as Player).queued = actions


## The factor of every Examine announced, as [who examined, factor], in order. The IFP are
## announced before the turn is, so each waits for the turn that names its author.
func _record(m: EncounterManager) -> Array:
	var seen: Array = []
	var pending: Array = []
	m.ifp_earned.connect(
		func(_species, action, _forlorn, _effective, factor):
			if action == GameEnums.IfpAction.EXAMINE_RIVAL:
				pending.append(factor)
	)
	m.turn_taken.connect(
		func(who, _action, _lines):
			for factor in pending:
				seen.append([who, factor])
			pending.clear()
	)
	return seen


func _factors(seen: Array) -> Array:
	var out: Array = []
	for entry in seen:
		out.append(snappedf(entry[1], 0.0001))
	return out


# --------------------------------------------------------------------------
# GameSession: factor to whole points
# --------------------------------------------------------------------------


func _check_rounding() -> void:
	print("[rounding]")
	_check(GameSession.scale_amount(6, 1.0) == 6, "no factor, no change")
	_check(GameSession.scale_amount(6, 1.1) == 7, "+10 % on 6 IFP rounds up to 7")
	_check(GameSession.scale_amount(9, 1.1) == 10, "...and on 9 to 10")
	_check(GameSession.scale_amount(10, 1.1) == 11, "float noise does not cost a point (10 * 1.1)")
	_check(GameSession.scale_amount(6, 1.4) == 9, "+40 % on 6 is 8.4, rounded up to 9")
	_check(GameSession.scale_amount(2, 0.64) == 1, "a penalty rounds down: 2 * 0.64 is 1")
	_check(GameSession.scale_amount(1, 0.64) == 0, "...and takes a lone point away")
	_check(GameSession.scale_amount(0, 1.4) == 0, "nothing stays nothing")


func _check_award() -> void:
	print("[award_ifp]")
	var species := &"examine_yield_test_species"
	var saved: Dictionary = GameSession.encyclopaedia.to_dict()
	GameSession.encyclopaedia.clear()
	var plain := GameSession.ifp_amount(GameEnums.IfpAction.EXAMINE_RIVAL, false)
	var got := GameSession.award_ifp(
		species, GameEnums.IfpAction.EXAMINE_RIVAL, false, true, 1.0 + 4 * _step()
	)
	_check(
		got == GameSession.scale_amount(plain, 1.0 + 4 * _step()) and got > plain,
		"an Examine with a bonus is worth more than the table's %d (%d)" % [plain, got]
	)
	_check(GameSession.page_ifp(species) == got, "...and the page receives what was awarded")
	GameSession.encyclopaedia.from_dict(saved)


func _check_weakness_award() -> void:
	print("[weakness info in the encyclopaedia]")
	var species := &"examine_weakness_test_species"
	var saved: Dictionary = GameSession.encyclopaedia.to_dict()
	GameSession.encyclopaedia.clear()
	var got := GameSession.award_ifp(species, GameEnums.IfpAction.WEAKNESS_INFO)
	_check(got == Model.IFP_PER_FRAGMENT, "the info is one fragment's worth (%d)" % got)
	_check(
		(
			GameSession.encyclopaedia.true_fragments(species) == 1
			and GameSession.encyclopaedia.parasitic_fragments(species) == 1
		),
		"...which forms a true fragment and a parasitic one"
	)
	GameSession.add_ifp(species, 200)
	_check(
		(
			GameSession.award_ifp(species, GameEnums.IfpAction.WEAKNESS_INFO) == 0
			and GameSession.page_ifp(species) == 99
		),
		"a page at 99 % takes no more of it"
	)
	GameSession.encyclopaedia.from_dict(saved)


## The WEAKNESS_INFO announcements of an encounter, as the species they name.
func _record_weakness(m: EncounterManager) -> Array:
	var seen: Array = []
	m.ifp_earned.connect(
		func(species, action, _forlorn, _effective, factor):
			if action == GameEnums.IfpAction.WEAKNESS_INFO and factor == 1.0:
				seen.append(species)
	)
	return seen


## `who` strikes `target`, whose exposed weakness is first made the ability's own, or not.
func _strike(
	m: EncounterManager, who: EncounterIndividual, target: EncounterIndividual, matching: bool
) -> void:
	var ability := _ability(&"brooding_fire")
	var energy := ability.energy
	var other := GameEnums.Energy.CRYSTAL
	if energy == other:
		other = GameEnums.Energy.HEAT
	target.override_weakness(energy if matching else other, target, 5)
	_play(m, who, [EncounterAction.use_ability(ability, [target])])


func _check_examine_weakness() -> void:
	print("[examine weakness]")
	_check_weakness_award()
	# The bearer strikes a rival's weakness: info on the rival.
	var m := _encounter(&"gelmi")
	var seen := _record_weakness(m)
	_strike(m, m.players[0], m.rivals[0], true)
	await m.run(1)
	_check(seen == [&"skorpis"], "striking a rival's weakness announces info on it (%s)" % [seen])
	m.free()

	# The weakness is not struck: nothing.
	m = _encounter(&"gelmi")
	seen = _record_weakness(m)
	_strike(m, m.players[0], m.rivals[0], false)
	await m.run(1)
	_check(seen.is_empty(), "a weakness that is not touched yields nothing")
	m.free()

	# The talent belongs to the species: a duo without it gets nothing.
	m = _encounter(&"kalilk")
	seen = _record_weakness(m)
	_strike(m, m.players[0], m.rivals[0], true)
	await m.run(1)
	_check(seen.is_empty(), "a duo without the talent gets no info")
	m.free()

	# The bearer is struck on its weakness by a rival: info on that rival.
	m = _encounter(&"gelmi")
	seen = _record_weakness(m)
	_strike(m, m.rivals[0], m.players[0], true)
	await m.run(1)
	_check(
		seen == [&"skorpis"], "being struck on its weakness gives info on the user (%s)" % [seen]
	)
	m.free()

	# ...but not on its own teammate.
	m = _encounter(&"gelmi")
	seen = _record_weakness(m)
	_strike(m, m.players[1], m.players[0], true)
	await m.run(1)
	_check(seen.is_empty(), "...nor when the user is a teammate")
	m.free()

	# A rival bearing the talent earns the player nothing.
	var all: Array = []
	for id in [&"kalilk", &"fliritus", &"gelmi", &"gelmi"]:
		all.append(EncounterManager.make_individual(id, all.size() < 2))
	m = EncounterManager.new()
	m.setup([all[0], all[1]], [all[2], all[3]], 20261022)
	m.timeline.order = all.duplicate()
	for f in all:
		m.set_agent(f, Player.new())
		f.eth = 20
	seen = _record_weakness(m)
	_strike(m, all[0], all[2], true)
	await m.run(1)
	_check(seen.is_empty(), "a rival's Examine Weakness has no encyclopaedia to fill")
	m.free()


# --------------------------------------------------------------------------
# In an encounter
# --------------------------------------------------------------------------


func _check_plain() -> void:
	print("[plain examine]")
	var m := _encounter()
	_play(m, m.players[0], [_examine(m.rivals[0])])
	var seen := _record(m)
	await m.run(1)
	_check(_factors(seen) == [1.0], "an Examine with nothing on it yields the table's amount")
	m.free()


func _check_catatonia() -> void:
	print("[catatonia]")
	var m := _encounter()
	var p0: EncounterIndividual = m.players[0]
	_play(m, p0, [_use(&"catatonia", p0), _examine(m.rivals[0]), _examine(m.rivals[0])])
	var seen := _record(m)
	await m.run(3)
	# Nobody hurt it: one step, two points.
	_check(
		_factors(seen) == [snappedf(1.0 + 2 * _step(), 0.0001), 1.0],
		"the next Examine yields more, the one after is plain (%s)" % [_factors(seen)]
	)
	_check(p0.examine_bonus_points == 0, "the bonus is gone afterwards")
	m.free()

	# Unused, it does not wait for a later Examine.
	m = _encounter()
	p0 = m.players[0]
	_play(m, p0, [_use(&"catatonia", p0), _pass(p0), _examine(m.rivals[0])])
	seen = _record(m)
	await m.run(3)
	_check(_factors(seen) == [1.0], "unused, the bonus does not outlast the next turn")
	m.free()


func _check_priming() -> void:
	print("[priming]")
	var m := _encounter()
	var p0: EncounterIndividual = m.players[0]
	var p1: EncounterIndividual = m.players[1]
	_play(m, p0, [_use(&"priming", p1), _examine(m.rivals[0])])
	_play(m, p1, [_examine(m.rivals[0]), _examine(m.rivals[0]), _examine(m.rivals[0])])
	var seen := _record(m)
	await m.run(3)
	# Round 1: p1 examines before it is primed? p0 acts first and primes p1 at once. Priming moves
	# p1 to the front of round 2, ahead of p0, whose own Examine is not boosted.
	var boosted := snappedf(1.0 + 2 * _step(), 0.0001)
	var by_p1: Array = []
	var by_p0: Array = []
	for entry in seen:
		(by_p1 if entry[0] == p1 else by_p0).append(snappedf(entry[1], 0.0001))
	_check(by_p0 == [1.0], "the user's own Examine is not boosted (%s)" % [by_p0])
	_check(
		by_p1.size() == 3 and by_p1[0] == boosted and by_p1[1] == boosted and by_p1[2] == 1.0,
		"the teammate's Examines are boosted until the user's next turn, then not (%s)" % [by_p1]
	)
	m.free()


func _check_recon_glide() -> void:
	print("[reconnaissance glide]")
	var m := _encounter(&"ravbak")
	var p0: EncounterIndividual = m.players[0]
	var p1: EncounterIndividual = m.players[1]
	_check(m.examine_factor(p0, m.rivals[0]) == 1.1, "the talent alone: +10 %")
	_check(m.examine_factor(p1, m.rivals[0]) == 1.0, "...for its bearer only")
	_play(m, p0, [_use(&"priming", p0), _examine(m.rivals[0])])
	_play(m, p1, [_pass(p1), _examine(m.rivals[0])])
	var seen := _record(m)
	await m.run(2)
	# Round 2 opens with p1, which Priming moved to the front. It has the bonus and not the
	# talent; p0 has the talent and, Priming reaching teammates only, not the bonus.
	_check(
		_factors(seen) == [1.2, 1.1],
		"...and a teammate's bonus is separate (%s)" % [_factors(seen)]
	)
	m.free()

	# The talent multiplies the bonus rather than adding to it.
	m = _encounter(&"ravbak")
	p0 = m.players[0]
	p0.grant_examine_bonus_points(2, p0, 2)
	_check(
		is_equal_approx(m.examine_factor(p0, m.rivals[0]), (1.0 + 2 * _step()) * 1.1),
		"the talent multiplies the bonus"
	)
	m.free()
