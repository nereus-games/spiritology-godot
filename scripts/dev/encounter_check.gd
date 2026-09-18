## Headless check on the encounter: abilities run without corrupting the combat state, the loop
## is deterministic for a given seed, and every talent wires up its hooks. Exits 1 if any of that
## regresses.
##
## Run with: Godot --headless --path . res://scenes/dev/encounter_check.tscn
## As a start scene rather than --script; see geometry_check.gd.
##
## The manager deliberately ignores [GameSession] — see its `ifp_earned` and `object_consumed`
## signals, which the UI relays — so this harness plays the part the UI plays in game, and needs
## no autoload at all.
extends Node

const TalentCatalog := preload("res://scripts/encounter/talents/talent_catalog.gd")

const ABILITY_DIR := "res://data/abilities/"
const TALENT_IMPL_DIR := "res://scripts/encounter/talents/impl/"

## Reference seed for the replayed encounters. Any value would do; what matters is that it is
## FIXED, or determinism cannot be tested at all.
const SEED := 20260909

## The test field: two individuals per side, so that all of [EncounterContext]'s targeting
## helpers (allies / opponents / others / first_opponent_in_order) have something to answer with.
## An ability that finds no target would prove nothing.
const PLAYER_SPECIES: Array[StringName] = [&"kalilk", &"fliritus"]
const RIVAL_SPECIES: Array[StringName] = [&"ravbak", &"skorpis"]

## Any ability at all, handed to the talent hooks that expect one.
const SAMPLE_ABILITY := &"anomaly"

var _fails: Array[String] = []
var _rng := RandomNumberGenerator.new()


## An agent that plays scripted actions, to exercise the paths [AutoAgent] never takes: it only
## plays abilities and Meditate, so Talk, Examine, Use Object, Steal and Flee would be exercised
## by nothing.
class ScriptedAgent:
	extends EncounterAgent

	var queued: Array = []

	func decide(_individual: EncounterIndividual, _manager: EncounterManager) -> EncounterAction:
		return queued.pop_front() if not queued.is_empty() else null


## Plays scripted actions, then passes — and, every time it is asked, reports the moment through
## `spy`, which is how a check looks at the state as each turn begins.
class SpyAgent:
	extends EncounterAgent
	var queued: Array = []
	var spy: Callable

	func decide(individual: EncounterIndividual, manager: EncounterManager) -> EncounterAction:
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
	await get_tree().process_frame  # let the autoloads and the root settle
	_rng.seed = SEED
	_check_abilities()
	await _check_actions()
	await _check_determinism()
	await _check_loop_invariants()
	_check_unfinished_release()
	await _check_departures()
	await _check_effect_durations()
	_check_talents()
	print("")
	if _fails.is_empty():
		print("ALL OK")
	else:
		print("FAILURES: %s" % [_fails])
	get_tree().quit(0 if _fails.is_empty() else 1)


# --------------------------------------------------------------------------
# The test field
# --------------------------------------------------------------------------


## Four fresh individuals: [p0, p1, r0, r1]. Rebuilt for EVERY ability, since one that dissolves a
## side would leave the next ones with no targets.
func _fresh_individuals() -> Array:
	var out: Array = []
	for id in PLAYER_SPECIES:
		out.append(EncounterManager.make_individual(id, true))
	for id in RIVAL_SPECIES:
		out.append(EncounterManager.make_individual(id, false))
	return out


## A manager ready to run. [EncounterManager] is a Node that is never added to the tree, so the
## caller MUST `free()` it, or Godot reports leaked instances at exit.
func _make_manager(seed: int = SEED) -> EncounterManager:
	var individuals := _fresh_individuals()
	var m := EncounterManager.new()
	m.setup([individuals[0], individuals[1]], [individuals[2], individuals[3]], seed)
	return m


func _ability_files() -> Array:
	var out: Array = []
	var dir := DirAccess.open(ABILITY_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".tres"):
			out.append(ABILITY_DIR + f)
	out.sort()  # a stable order keeps the check's output comparable between runs
	return out


# --------------------------------------------------------------------------
# Abilities: each one runs and leaves the combat state consistent
# --------------------------------------------------------------------------


func _check_abilities() -> void:
	print("— abilities —")
	var executed := 0
	var broken: Array[String] = []
	for path in _ability_files():
		var res := load(path)
		if not (res is AbilityData):
			continue  # TalentData live in the same directory; see _check_talents
		var ability: AbilityData = res
		if ability.type != GameEnums.AbilityType.ENCOUNTER:
			continue  # exploration abilities have an execution path of their own
		executed += 1
		var problem := _execute_ability(ability)
		if problem != "":
			broken.append("%s (%s)" % [ability.id, problem])
	_check(executed >= 100, "%d encounter abilities executed" % executed)
	_check(
		broken.is_empty(),
		(
			"combat state sound after every ability%s"
			% ("" if broken.is_empty() else " — " + ", ".join(broken))
		)
	)


## Runs one ability on a fresh field. Returns "" when the state stays consistent, and a
## description of the problem otherwise.
func _execute_ability(ability: AbilityData) -> String:
	var individuals := _fresh_individuals()
	var timeline := EncounterTimeline.new()
	timeline.setup(individuals)  # no rng: a stable order, so known positions and weaknesses
	var ctx := EncounterContext.new()
	ctx.ability = ability
	ctx.user = individuals[0]
	ctx.targets = [individuals[2]]
	ctx.all_individuals = individuals
	ctx.timeline = timeline
	ctx.rng = _rng
	# A concrete energy rather than NONE, which is what sends the Random and Variable abilities
	# down the real path — modifiers, immunities — instead of the short circuit.
	ctx.resolved_energy = GameEnums.Energy.HEAT
	EffectCatalog.script_for(ability).execute(ctx)
	var problem := _state_problem(individuals, timeline)
	# These individuals never go through EncounterManager._finish(), so their reference cycles have
	# to be broken here, or the 108 test fields leak.
	for f in individuals:
		f.release_cross_references()
	return problem


## Invariants NO ability may be allowed to break.
func _state_problem(individuals: Array, timeline: EncounterTimeline) -> String:
	for f in individuals:
		if f.den < 0 or f.den > f.max_den:
			return "DEN %d outside [0, %d] on %s" % [f.den, f.max_den, f.species_id()]
		if f.eth < 0 or f.eth > f.max_eth:
			return "ETH %d outside [0, %d] on %s" % [f.eth, f.max_eth, f.species_id()]
	# Reorderings are queued and applied at the end of the turn, so applying them here is the only
	# way to see the order an ability actually asked for.
	timeline.apply_pending()
	if timeline.order.size() != individuals.size():
		return (
			"turn order has %d entries instead of %d" % [timeline.order.size(), individuals.size()]
		)
	for f in individuals:
		if not timeline.order.has(f):
			return "%s missing from the turn order" % f.species_id()
	return ""


# --------------------------------------------------------------------------
# Actions: every kind of turn resolves and leaves the state consistent
# --------------------------------------------------------------------------


## Exercises the eight [enum EncounterAction.Kind] through the PUBLIC loop — a scripted agent
## forces the action, `run()` resolves it. Calling `_resolve_action()` directly would test the
## resolver without its context; this tests what the game actually runs.
func _check_actions() -> void:
	print("— actions —")
	var untested: Array[String] = []
	var broken: Array[String] = []
	for kind in EncounterAction.Kind.values():
		var m := _make_manager()
		var actor: EncounterIndividual = m.players[0]
		var target: EncounterIndividual = m.rivals[0]
		# The manager ignores the autoloads: in game the UI resolves objects for it.
		m.object_provider = func(id): return load("res://data/objects/%s.tres" % id)
		var agent := ScriptedAgent.new()
		agent.queued = [_action_of_kind(kind, actor, target, m)]
		m.set_agent(actor, agent)
		# Listen to THIS actor's turn: `run(1)` makes the others play too, so the log would grow
		# even if the forced action produced nothing.
		var spoke := [false]
		m.turn_taken.connect(
			func(f, _a, lines):
				if f == actor and not lines.is_empty():
					spoke[0] = true
		)
		await m.run(1)
		if not spoke[0]:
			untested.append(EncounterAction.Kind.keys()[kind])
		var problem := _state_problem(m.players + m.rivals, m.timeline)
		if problem != "":
			broken.append("%s (%s)" % [EncounterAction.Kind.keys()[kind], problem])
		m.free()
	_check(
		untested.is_empty(),
		(
			"every kind of action produces a log line%s"
			% ("" if untested.is_empty() else " — silent: " + ", ".join(untested))
		)
	)
	_check_empty(broken, "combat state sound after every kind of action")


func _action_of_kind(
	kind: int, actor: EncounterIndividual, target: EncounterIndividual, m: EncounterManager
) -> EncounterAction:
	match kind:
		EncounterAction.Kind.ABILITY:
			var usable := m.usable_abilities(actor)
			var ability: AbilityData = usable[0] if not usable.is_empty() else null
			return EncounterAction.use_ability(ability, [target])
		EncounterAction.Kind.USE_OBJECT:
			var a := EncounterAction.of_kind(EncounterAction.Kind.USE_OBJECT, [target])
			a.object_id = &"rune_stone"
			return a
		EncounterAction.Kind.MEDITATE, EncounterAction.Kind.PASS:
			return EncounterAction.of_kind(kind, [actor])
		_:
			return EncounterAction.of_kind(kind, [target])


## A failure listing the offenders, in the same shape as the project's other checks.
func _check_empty(offenders: Array, label: String) -> void:
	if offenders.is_empty():
		_check(true, label)
		return
	_check(false, "%s — %s" % [label, ", ".join(offenders)])


# --------------------------------------------------------------------------
# Determinism: what will make any refactor of the loop verifiable
# --------------------------------------------------------------------------


func _check_determinism() -> void:
	print("— determinism —")
	var a := await _run_once(SEED)
	var b := await _run_once(SEED)
	_check(a["result"] == b["result"], "same seed, same outcome (%s)" % a["result"])
	_check(a["rounds"] == b["rounds"], "same seed, same number of rounds (%d)" % a["rounds"])
	_check(a["log"] == b["log"], "same seed, same log (%d lines)" % a["log"].size())
	# A negative control: without it the assertions above would pass just as well on an encounter
	# where the rng drove nothing at all. Initial turn orders are compared — 24 permutations for 4
	# individuals — rather than two logs, which could coincide by chance on a short fight.
	var orders := {}
	for i in 10:
		var m := _make_manager(SEED + i)
		orders[",".join(m.timeline.order.map(func(f): return String(f.species_id())))] = true
		m.free()
	_check(
		orders.size() > 1,
		"different seeds, different turn orders (%d distinct out of 10)" % orders.size()
	)


func _run_once(seed: int) -> Dictionary:
	var m := _make_manager(seed)
	var res := await m.run()
	var out := {"result": res, "log": m.encounter_log, "rounds": m.round_number}
	m.free()
	return out


# --------------------------------------------------------------------------
# How long effects last
# --------------------------------------------------------------------------


## "Until its next turn" means the next turn of whoever caused it — not the end of the round.
## Effort of Neutrality played SECOND in the order used to hand both weaknesses back as the
## next round began, before either individual had acted again: the bug seen in game.
func _check_effect_durations() -> void:
	print("— effect durations —")
	var m := _make_manager()
	var p0: EncounterIndividual = m.players[0]
	var p1: EncounterIndividual = m.players[1]
	m.timeline.order = [p0, p1, m.rivals[0], m.rivals[1]]  # a known order, hence known positions
	var seen := {}  # "round:species" -> the weaknesses of p0 and p1 as that turn began
	var spy := func(f: EncounterIndividual, mgr: EncounterManager) -> void:
		seen["%d:%s" % [mgr.round_number, f.species_id()]] = [
			p0.active_weakness(mgr.timeline.position_of(p0)),
			p1.active_weakness(mgr.timeline.position_of(p1)),
		]
	for f in m.timeline.order:
		var agent := SpyAgent.new()
		agent.spy = spy
		m.set_agent(f, agent)
	var neutrality: AbilityData = load(ABILITY_DIR + "effort_of_neutrality.tres")
	(m.agent_for(p1) as SpyAgent).queued = [EncounterAction.use_ability(neutrality, [p1])]
	await m.run(2)
	var none := GameEnums.Energy.NONE
	var p0_own := p0.species.weakness_for(GameEnums.TurnPosition.FIRST)
	var p1_own := p1.species.weakness_for(GameEnums.TurnPosition.MIDDLE)
	_check(p0_own != none and p1_own != none, "both test species expose a weakness of their own")
	_check(
		seen.get("2:%s" % p0.species_id()) == [none, none],
		"no weakness for either teammate across the round boundary"
	)
	_check(
		seen.get("2:%s" % p1.species_id(), [])[1] == p1_own,
		"the user's own weakness back as its next turn begins"
	)
	m.free()


# --------------------------------------------------------------------------
# The loop: positions, weaknesses, termination
# --------------------------------------------------------------------------


func _check_loop_invariants() -> void:
	print("— loop —")
	var m := _make_manager()
	var order := m.timeline.order
	_check(order.size() == 4, "turn order: %d individuals" % order.size())
	_check(
		m.timeline.position_of(order[0]) == GameEnums.TurnPosition.FIRST,
		"head of the order is position FIRST"
	)
	_check(
		m.timeline.position_of(order[1]) == GameEnums.TurnPosition.MIDDLE,
		"middle of the order is position MIDDLE"
	)
	_check(
		m.timeline.position_of(order[3]) == GameEnums.TurnPosition.LAST,
		"tail of the order is position LAST"
	)
	# The active weakness comes from the POSITION, not from the individual: that is the rule that
	# makes reordering abilities offensive.
	var head: EncounterIndividual = order[0]
	_check(
		(
			head.active_weakness(GameEnums.TurnPosition.FIRST) == head.species.weakness_first
			and head.active_weakness(GameEnums.TurnPosition.LAST) == head.species.weakness_last
		),
		"active weakness derived from the position"
	)
	m.free()

	# Termination: the loop always returns one of the three outcomes and respects max_rounds.
	var m2 := _make_manager()
	var res := await m2.run(3)
	_check(res in [&"victory", &"defeat", &"timeout"], "valid outcome: %s" % res)
	_check(
		m2.round_number >= 1 and m2.round_number <= 3,
		"rounds bounded by max_rounds (%d)" % m2.round_number
	)
	_check(m2.result == res, "the result field reflects the outcome returned")
	_check(
		not m2.encounter_log.is_empty(),
		"the encounter produced a log (%d lines)" % m2.encounter_log.size()
	)
	m2.free()


## An encounter freed before it ends never reaches [method EncounterManager._finish], and must
## still break its individuals' cycles. Both shapes are built here: two individuals that hit each
## other, and one hurt by its own ability, which is its own last damager. A leak shows twice —
## these weak references survive the manager, and `run_checks.sh` sees "leaked at exit".
func _check_unfinished_release() -> void:
	print("— unfinished encounter —")
	var refs := _abandon_encounter_with_cycles()
	var alive := 0
	for r in refs:
		if r.get_ref() != null:
			alive += 1
	_check(alive == 0, "individuals released when freed mid-encounter (%d still alive)" % alive)


## Returns weak references only, so that nothing in the caller keeps an individual alive.
func _abandon_encounter_with_cycles() -> Array:
	var m := _make_manager()
	var p0: EncounterIndividual = m.players[0]
	var r0: EncounterIndividual = m.rivals[0]
	var r1: EncounterIndividual = m.rivals[1]
	p0.last_damager = r0
	r0.last_damager = p0
	r1.last_damager = r1
	var refs := [weakref(p0), weakref(r0), weakref(r1)]
	m.free()
	return refs


# --------------------------------------------------------------------------
# Departures: leaving an encounter without dissolving anyone
# --------------------------------------------------------------------------


func _check_departures() -> void:
	print("— departures —")
	await _check_side_flight()
	await _check_lone_flight()
	await _check_rivals_leaving()
	await _check_flee_cost()
	_check_departure_and_reordering()


## Run Away takes out the character who runs, and only it: the encounter goes on with the
## teammate, and ends as a flight once the teammate has run too.
func _check_side_flight() -> void:
	var m := _make_manager()
	var first: EncounterIndividual = m.players[0]
	var second: EncounterIndividual = m.players[1]
	var agent := ScriptedAgent.new()
	agent.queued = [EncounterAction.of_kind(EncounterAction.Kind.FLEE)]
	m.set_agent(first, agent)
	var res := await m.run(1)
	_check(first.departure == EncounterManager.FLED, "Run Away takes the character out")
	_check(
		second.departure == &"" and m.players == [second] and res != &"fled",
		"the teammate stays, and the encounter goes on (%s)" % res
	)
	m.free()

	var m2 := _make_manager()
	for f in m2.players:
		var runner := ScriptedAgent.new()
		runner.queued = [EncounterAction.of_kind(EncounterAction.Kind.FLEE)]
		m2.set_agent(f, runner)
	var res2 := await m2.run(1)
	_check(res2 == &"fled", "both characters run: the encounter ends as a flight (%s)" % res2)
	_check(
		m2.players.is_empty() and m2.timeline.order.all(func(f): return not f.is_player),
		"the duo is out of its side and out of the turn order"
	)
	var outcomes: Array = m2.rival_report().map(func(r): return r["outcome"])
	_check(outcomes == [&"stayed", &"stayed"], "the report leaves the rivals in (%s)" % [outcomes])
	m2.free()

	# A smoke bomb sends running the character it is used on — here, the teammate.
	var m3 := _make_manager()
	m3.object_provider = func(id): return load("res://data/objects/%s.tres" % id)
	var user: EncounterIndividual = m3.players[0]
	var mate: EncounterIndividual = m3.players[1]
	var bomb := EncounterAction.of_kind(EncounterAction.Kind.USE_OBJECT, [mate])
	bomb.object_id = &"smoke_bomb"
	var agent3 := ScriptedAgent.new()
	agent3.queued = [bomb]
	m3.set_agent(user, agent3)
	await m3.run(1)
	_check(
		mate.departure == EncounterManager.FLED and user.departure == &"",
		"a smoke bomb sends running the character it is used on, and only it"
	)
	m3.free()


## Opening up Closing makes its user flee ALONE: the teammate carries on, and the user neither acts
## again nor can be aimed at.
func _check_lone_flight() -> void:
	var m := _make_manager()
	var actor: EncounterIndividual = m.players[0]
	var teammate: EncounterIndividual = m.players[1]
	var ability := m.resolve_ability(&"opening_up_closing")
	var agent := ScriptedAgent.new()
	agent.queued = [
		EncounterAction.use_ability(ability, [m.rivals[0]]),
		EncounterAction.of_kind(EncounterAction.Kind.PASS),
	]
	m.set_agent(actor, agent)
	var res := await m.run(2)
	_check(actor.departure == EncounterManager.FLED, "Opening up Closing: its user leaves")
	_check(teammate.departure == &"" and m.players == [teammate], "the teammate stays in")
	_check(res != &"fled", "one character leaving does not end the encounter (%s)" % res)
	_check(agent.queued.size() == 1, "a character who left takes no further turn")
	_check(
		not m.opponents_of(m.rivals[0]).has(actor) and not m.timeline.order.has(actor),
		"a character who left can no longer be aimed at"
	)
	m.free()

	# The flight is resolved at the END of the turn: an individual the same ability dissolves is
	# dissolved, not gone.
	var m2 := _make_manager()
	var doomed: EncounterIndividual = m2.players[0]
	doomed.den = 1
	var agent2 := ScriptedAgent.new()
	agent2.queued = [EncounterAction.use_ability(ability, [m2.rivals[0]])]
	m2.set_agent(doomed, agent2)
	await m2.run(1)
	_check(
		doomed.is_dissolved() and not doomed.has_left(),
		"an individual dissolved by its own flight stays dissolved"
	)
	m2.free()


## The rivals' side: every rival gone decides the outcome, according to how they went.
func _check_rivals_leaving() -> void:
	var m := _make_manager()
	for r in m.rivals.duplicate():
		m.pacify(r)
	var res := await m.run(1)
	_check(res == &"pacified", "every rival pacified ends the encounter as pacified (%s)" % res)
	var outcomes: Array = m.rival_report().map(func(r): return r["outcome"])
	_check(outcomes == [&"pacified", &"pacified"], "the report says so (%s)" % [outcomes])
	m.free()

	var m2 := _make_manager()
	var runner: EncounterIndividual = m2.rivals[0]
	var fallen: EncounterIndividual = m2.rivals[1]
	m2.withdraw(runner, EncounterManager.FLED)
	fallen.den = 0
	var res2 := await m2.run(1)
	_check(
		res2 == &"rivals_fled", "one rival fled and the other dissolved: rivals_fled (%s)" % res2
	)
	var report := m2.rival_report()
	_check(
		report[0]["outcome"] == &"fled" and report[0]["den"] == runner.den,
		"the report keeps the fled rival's DEN (%d)" % runner.den
	)
	_check(report[1]["outcome"] == &"dissolved", "and records the dissolved one")
	m2.free()

	var m3 := _make_manager()
	for r in m3.rivals:
		r.den = 0
	var res3 := await m3.run(1)
	_check(res3 == &"victory", "every rival dissolved is still a victory (%s)" % res3)
	m3.free()


## Slick Merchant's Run Away costs 10 ETH, and does nothing when that cannot be paid.
func _check_flee_cost() -> void:
	var merchant := EncounterManager.make_individual(&"fopin", true)
	var teammate := EncounterManager.make_individual(&"kalilk", true)
	var rivals := [
		EncounterManager.make_individual(&"ravbak", false),
		EncounterManager.make_individual(&"skorpis", false)
	]
	var m := EncounterManager.new()
	m.setup([merchant, teammate], rivals, SEED)
	_check(m.flee_cost(merchant) == 10, "Slick Merchant: Run Away costs 10 ETH")
	_check(m.flee_cost(teammate) == 0, "everyone else runs for free")
	merchant.eth = 4
	var agent := ScriptedAgent.new()
	agent.queued = [EncounterAction.of_kind(EncounterAction.Kind.FLEE)]
	m.set_agent(merchant, agent)
	await m.run(1)
	_check(not merchant.has_left(), "without the ETH, Slick Merchant stays")
	m.free()

	var merchant2 := EncounterManager.make_individual(&"fopin", true)
	var m2 := EncounterManager.new()
	m2.setup(
		[merchant2, EncounterManager.make_individual(&"kalilk", true)],
		[
			EncounterManager.make_individual(&"ravbak", false),
			EncounterManager.make_individual(&"skorpis", false)
		],
		SEED
	)
	merchant2.eth = 25
	var agent2 := ScriptedAgent.new()
	agent2.queued = [EncounterAction.of_kind(EncounterAction.Kind.FLEE)]
	m2.set_agent(merchant2, agent2)
	await m2.run(1)
	_check(merchant2.has_left(), "with the ETH, Slick Merchant gets away")
	_check(merchant2.eth == 15, "and pays 10 ETH for it (%d left)" % merchant2.eth)
	m2.free()


## A reordering queued before someone leaves must not put them back in the order.
func _check_departure_and_reordering() -> void:
	var m := _make_manager()
	var leaving: EncounterIndividual = m.players[0]
	m.timeline.request_move_last(leaving)
	m.withdraw(leaving, EncounterManager.FLED)
	m.timeline.apply_pending()
	_check(not m.timeline.order.has(leaving), "a pending reordering does not bring back who left")
	_check(m.timeline.order.size() == 3, "and keeps everyone else (%d)" % m.timeline.order.size())
	m.free()


# --------------------------------------------------------------------------
# Talents: each resolves to its dedicated script and answers every hook
# --------------------------------------------------------------------------


func _check_talents() -> void:
	print("— talents —")
	var m := _make_manager()
	var owner: EncounterIndividual = m.players[0]
	var other: EncounterIndividual = m.rivals[0]
	var sample := m.resolve_ability(SAMPLE_ABILITY)
	var resolved := 0
	var problems: Array[String] = []
	for path in _ability_files():
		var res := load(path)
		if not (res is TalentData):
			continue
		var td: TalentData = res
		var impl := TALENT_IMPL_DIR + String(td.id) + ".gd"
		if not ResourceLoader.exists(impl):
			problems.append("%s has no dedicated script" % td.id)
			continue
		var script = TalentCatalog.script_for(td, owner, 1)
		if script.get_script().resource_path != impl:
			problems.append("%s does not resolve to its script" % td.id)
			continue
		resolved += 1
		# Every hook, in the order the loop calls them. Talents that are still stubs must stay
		# no-op: doing nothing is a valid answer, failing is not.
		script.on_encounter_start(m)
		script.modify_talk_chance(m, owner, other, 0.3)
		script.on_talk_resolved(m, owner, other, true)
		script.allows_ally_talk(m)
		script.wants_reuse(m, owner, sample)
		script.on_weakness_touched(m, owner, other, sample)
		script.modify_examine_info(m, other, 1.0)
		var kinds: Array = [
			EncounterAction.Kind.ABILITY, EncounterAction.Kind.TALK, EncounterAction.Kind.EXAMINE
		]
		script.modify_menu(m, kinds)
		if kinds.is_empty():
			problems.append("%s empties the action menu" % td.id)
		script.on_encounter_end(m, &"victory")
	_check(resolved == 10, "%d talents resolved to their dedicated script" % resolved)
	_check(
		problems.is_empty(),
		"talent hooks working%s" % ("" if problems.is_empty() else " — " + ", ".join(problems))
	)
	m.free()
