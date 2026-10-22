## Headless check on the teammate's refusals above PSY rung 4: the first action of a dungeon
## visit's first encounter is always refused, every later one by chance, the refusal costs the
## action, and the whole thing is reproducible for a given seed.
##
## Run with: Godot --headless --path . res://scenes/dev/psy_refusal_check.tscn
## As a start scene rather than --script; see geometry_check.gd.
extends Node

const SEED := 20261022
const ROUNDS := 40

var _fails: Array[String] = []


## Passes every turn, or plays a queued action first.
class PassAgent:
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
	var balance := BalanceData.current()
	var saved_chance := balance.psy_teammate_refusal_chance
	await _check_refusals()
	balance.psy_teammate_refusal_chance = saved_chance
	_check_session()
	print("")
	if _fails.is_empty():
		print("ALL OK")
	else:
		print("FAILURES: %s" % [_fails])
	get_tree().quit(0 if _fails.is_empty() else 1)


## Runs ROUNDS rounds of passing and returns, per teammate turn, whether it refused. `arm` says
## whether to arm the refusal at all, `first` whether the first action is a sure refusal.
func _play(arm: bool, first: bool, chance: float, seed: int = SEED) -> Array:
	BalanceData.current().psy_teammate_refusal_chance = chance
	var players := [
		EncounterManager.make_individual(&"kalilk", true),
		EncounterManager.make_individual(&"fliritus", true)
	]
	var rivals := [
		EncounterManager.make_individual(&"ravbak", false),
		EncounterManager.make_individual(&"skorpis", false)
	]
	var m := EncounterManager.new()
	m.setup(players, rivals, seed)
	for f in players + rivals:
		m.set_agent(f, PassAgent.new())
	if arm:
		m.enable_refusal(players[1], first)
	var line: String = m._tr("LOG_TEAMMATE_REFUSES")
	var refusals: Array = []
	m.turn_taken.connect(_note_turn.bind(players[1], line, refusals))
	await m.run(ROUNDS)
	m.free()
	return refusals


## Records, for each turn the teammate takes, whether the turn was a refusal.
func _note_turn(
	who: EncounterIndividual,
	_action: EncounterAction,
	lines: PackedStringArray,
	teammate: EncounterIndividual,
	refusal_line: String,
	refusals: Array
) -> void:
	if who == teammate:
		refusals.append(refusal_line in lines)


func _count(flags: Array) -> int:
	var n := 0
	for f in flags:
		if f:
			n += 1
	return n


func _check_refusals() -> void:
	var off := await _play(false, true, 1.0)
	_check(off.size() > 0 and _count(off) == 0, "unarmed, the teammate never refuses")

	var first_only := await _play(true, true, 0.0)
	_check(
		first_only.size() > 1 and first_only[0] and _count(first_only) == 1,
		"first action refused, none after at chance 0 (%d)" % _count(first_only)
	)

	var later_only := await _play(true, false, 0.0)
	_check(_count(later_only) == 0, "not a first encounter: no sure refusal, none at chance 0")

	var always := await _play(true, false, 1.0)
	_check(
		always.size() > 0 and _count(always) == always.size(), "at chance 1 every action is refused"
	)

	var a := await _play(true, true, 0.2)
	var b := await _play(true, true, 0.2)
	_check(a == b, "the same seed refuses the same actions")
	_check(a[0], "with the real chance, the first action is still refused")
	var later := _count(a) - 1
	_check(
		later > 0 and later < a.size() - 1,
		"and later ones are refused only some of the time (%d)" % later
	)
	var c := await _play(true, true, 0.2, SEED + 1)
	_check(a != c, "another seed refuses differently")

	# A refused action costs the action: Meditate does not restore the ETH.
	BalanceData.current().psy_teammate_refusal_chance = 0.0
	for armed in [true, false]:
		var players := [
			EncounterManager.make_individual(&"kalilk", true),
			EncounterManager.make_individual(&"fliritus", true)
		]
		var rivals := [EncounterManager.make_individual(&"ravbak", false)]
		var m := EncounterManager.new()
		m.setup(players, rivals, SEED)
		for f in players + rivals:
			m.set_agent(f, PassAgent.new())
		var agent := PassAgent.new()
		agent.queued = [EncounterAction.of_kind(EncounterAction.Kind.MEDITATE, [players[1]])]
		m.set_agent(players[1], agent)
		if armed:
			m.enable_refusal(players[1], true)
		players[1].eth = 10
		await m.run(1)
		if armed:
			_check(players[1].eth == 10, "a refused Meditate restores nothing")
		else:
			_check(players[1].eth > 10, "control: the same Meditate restores ETH when not refused")
		m.free()


func _check_session() -> void:
	var saved := GameSession.psy_score
	GameSession.psy_score = 40
	_check(not GameSession.psy_above(4), "PSY 40 is not above rung 4")
	GameSession.psy_score = 41
	_check(GameSession.psy_above(4), "PSY 41 is above rung 4")
	GameSession.psy_score = saved
	GameSession.begin_dungeon_visit()
	_check(
		GameSession.take_first_encounter(), "entering a dungeon: the next encounter is the first"
	)
	_check(not GameSession.take_first_encounter(), "and only the first")
	GameSession.begin_dungeon_visit()
	_check(GameSession.take_first_encounter(), "entering another dungeon resets it")
	GameSession.first_encounter_pending = true
