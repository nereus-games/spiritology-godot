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

	func decide(_fighter: EncounterFighter, _manager: EncounterManager) -> EncounterAction:
		return queued.pop_front() if not queued.is_empty() else null


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


## Four fresh fighters: [p0, p1, r0, r1]. Rebuilt for EVERY ability, since one that dissolves a
## side would leave the next ones with no targets.
func _fresh_fighters() -> Array:
	var out: Array = []
	for id in PLAYER_SPECIES:
		out.append(EncounterManager.make_fighter(id, true))
	for id in RIVAL_SPECIES:
		out.append(EncounterManager.make_fighter(id, false))
	return out


## A manager ready to run. [EncounterManager] is a Node that is never added to the tree, so the
## caller MUST `free()` it, or Godot reports leaked instances at exit.
func _make_manager(seed: int = SEED) -> EncounterManager:
	var fighters := _fresh_fighters()
	var m := EncounterManager.new()
	m.setup([fighters[0], fighters[1]], [fighters[2], fighters[3]], seed)
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
	var fighters := _fresh_fighters()
	var timeline := EncounterTimeline.new()
	timeline.setup(fighters)  # no rng: a stable order, so known positions and weaknesses
	var ctx := EncounterContext.new()
	ctx.ability = ability
	ctx.user = fighters[0]
	ctx.targets = [fighters[2]]
	ctx.all_fighters = fighters
	ctx.timeline = timeline
	ctx.rng = _rng
	# A concrete energy rather than NONE, which is what sends the Random and Variable abilities
	# down the real path — modifiers, immunities — instead of the short circuit.
	ctx.resolved_energy = GameEnums.Energy.HEAT
	EffectCatalog.script_for(ability).execute(ctx)
	var problem := _state_problem(fighters, timeline)
	# These fighters never go through EncounterManager._finish(), so their reference cycles have
	# to be broken here, or the 108 test fields leak.
	for f in fighters:
		f.release_cross_references()
	return problem


## Invariants NO ability may be allowed to break.
func _state_problem(fighters: Array, timeline: EncounterTimeline) -> String:
	for f in fighters:
		if f.den < 0 or f.den > f.max_den:
			return "DEN %d outside [0, %d] on %s" % [f.den, f.max_den, f.species_id()]
		if f.eth < 0 or f.eth > f.max_eth:
			return "ETH %d outside [0, %d] on %s" % [f.eth, f.max_eth, f.species_id()]
	# Reorderings are queued and applied at the end of the turn, so applying them here is the only
	# way to see the order an ability actually asked for.
	timeline.apply_pending()
	if timeline.order.size() != fighters.size():
		return "turn order has %d entries instead of %d" % [timeline.order.size(), fighters.size()]
	for f in fighters:
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
		var actor: EncounterFighter = m.players[0]
		var target: EncounterFighter = m.rivals[0]
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
	kind: int, actor: EncounterFighter, target: EncounterFighter, m: EncounterManager
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
	# fighters — rather than two logs, which could coincide by chance on a short fight.
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
	var out := {"result": res, "log": m.battle_log, "rounds": m.round_number}
	m.free()
	return out


# --------------------------------------------------------------------------
# The loop: positions, weaknesses, termination
# --------------------------------------------------------------------------


func _check_loop_invariants() -> void:
	print("— loop —")
	var m := _make_manager()
	var order := m.timeline.order
	_check(order.size() == 4, "turn order: %d fighters" % order.size())
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
	var head: EncounterFighter = order[0]
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
		not m2.battle_log.is_empty(),
		"the encounter produced a log (%d lines)" % m2.battle_log.size()
	)
	m2.free()


# --------------------------------------------------------------------------
# Talents: each resolves to its dedicated script and answers every hook
# --------------------------------------------------------------------------


func _check_talents() -> void:
	print("— talents —")
	var m := _make_manager()
	var owner: EncounterFighter = m.players[0]
	var other: EncounterFighter = m.rivals[0]
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
