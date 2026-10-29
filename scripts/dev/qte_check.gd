## Headless check of the quick-time event behind Slick Merchant's Run Away: the pure rules of
## `qte.gd` (marker, zone, press, time limit), and what the manager does with a passed or failed
## attempt. The overlay that draws it is not covered here; it only keeps a clock and feeds the
## rules.
##
## Run with: Godot --headless --path . res://scenes/dev/qte_check.tscn
## As a start scene rather than --script; see geometry_check.gd.
extends Node

const Qte := preload("res://scripts/encounter/qte.gd")

var _fails: Array[String] = []


## Plays queued actions, then passes.
class Player:
	extends EncounterAgent
	var queued: Array = []

	func decide(individual: EncounterIndividual, _manager: EncounterManager) -> EncounterAction:
		if not queued.is_empty():
			return queued.pop_front()
		return EncounterAction.of_kind(EncounterAction.Kind.PASS, [individual])


## Stands in for the overlay: answers `verdict`, and remembers who it was asked about.
class FakeQte:
	extends RefCounted
	var verdict := true
	var asked: Array = []

	func play(who) -> bool:
		asked.append(who)
		await Engine.get_main_loop().process_frame  # a real one suspends the loop too
		return verdict


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
	_check_rules()
	await _check_manager()
	print("")
	if _fails.is_empty():
		print("ALL OK")
	else:
		print("FAILURES: %s" % [_fails])
	get_tree().quit(0 if _fails.is_empty() else 1)


func _check_rules() -> void:
	print("[qte rules]")
	var q = Qte.new()
	q.period = 2.0
	q.zone_center = 0.5
	q.zone_width = 0.2
	q.time_limit = 3.0
	_check(is_zero_approx(q.marker_at(0.0)), "the marker starts at one end")
	_check(is_equal_approx(q.marker_at(1.0), 1.0), "...reaches the other after half a period")
	_check(is_zero_approx(q.marker_at(2.0)), "...and is back after a whole one")
	_check(is_equal_approx(q.marker_at(0.5), 0.5), "...sweeping evenly")
	_check(is_equal_approx(q.marker_at(1.5), 0.5), "...in both directions")
	_check(q.in_zone(0.5) and q.in_zone(0.41) and q.in_zone(0.59), "the zone holds its centre")
	_check(not q.in_zone(0.39) and not q.in_zone(0.61), "...and not what lies outside it")
	_check(q.evaluate(0.5) == Qte.Outcome.HIT, "a press with the marker in the zone hits")
	_check(q.evaluate(1.5) == Qte.Outcome.HIT, "...on the way back as well")
	_check(q.evaluate(0.1) == Qte.Outcome.MISS, "a press with the marker outside misses")
	_check(q.evaluate(2.0) == Qte.Outcome.MISS, "...even where it has come back to the start")
	_check(q.evaluate(3.0) == Qte.Outcome.TIMEOUT, "the limit itself is too late")
	_check(q.evaluate(INF) == Qte.Outcome.TIMEOUT, "no press at all times out")
	_check(q.evaluate(-0.1) == Qte.Outcome.TIMEOUT, "a press before the start does not count")
	_check(
		Qte.succeeded(Qte.Outcome.HIT) and not Qte.succeeded(Qte.Outcome.MISS),
		"only a hit succeeds"
	)
	_check(not Qte.succeeded(Qte.Outcome.TIMEOUT), "...a timeout does not")
	var b := BalanceData.current()
	var d = Qte.from_balance()
	_check(
		d.period == b.qte_period and d.zone_width == b.qte_zone_width,
		"the figures come from balance.tres"
	)
	_check(d.evaluate(d.period / 4.0) == Qte.Outcome.HIT, "...and a press a quarter in hits")


## Two players and two rivals in the order [p0, p1, r0, r1].
func _encounter(first: StringName, rival: StringName = &"skorpis") -> EncounterManager:
	var all: Array = []
	for id in [first, &"fliritus"]:
		all.append(EncounterManager.make_individual(id, true))
	for id in [rival, &"skorpis"]:
		all.append(EncounterManager.make_individual(id, false))
	var m := EncounterManager.new()
	m.setup([all[0], all[1]], [all[2], all[3]], 20261022)
	m.timeline.order = all.duplicate()
	for f in all:
		m.set_agent(f, Player.new())
		f.eth = 20
	return m


func _flee(m: EncounterManager, who: EncounterIndividual) -> void:
	(m.agent_for(who) as Player).queued = [EncounterAction.of_kind(EncounterAction.Kind.FLEE)]


func _check_manager() -> void:
	print("[run away behind the qte]")
	var fake := FakeQte.new()

	# Skipped: nothing is there to play it, which is how every harness runs.
	var m := _encounter(&"fopin")
	var p0: EncounterIndividual = m.players[0]
	_check(m.flee_needs_qte(p0), "Slick Merchant's Run Away has a QTE")
	_flee(m, p0)
	await m.run(1)
	_check(p0.departure == EncounterManager.FLED, "[skipped] the attempt succeeds")
	_check(p0.eth == 10, "...and costs its 10 ETH")
	m.free()

	# Passed.
	m = _encounter(&"fopin")
	p0 = m.players[0]
	fake.verdict = true
	m.qte_runner = fake.play
	_flee(m, p0)
	await m.run(1)
	_check(fake.asked == [p0], "[passed] the player character is asked to play it")
	_check(p0.departure == EncounterManager.FLED, "...and runs away")
	m.free()

	# Failed.
	m = _encounter(&"fopin")
	p0 = m.players[0]
	fake.verdict = false
	fake.asked.clear()
	m.qte_runner = fake.play
	_flee(m, p0)
	var lines: Array = []
	m.turn_taken.connect(func(who, _a, l): lines.append([who, Array(l)]))
	await m.run(1)
	_check(fake.asked == [p0], "[failed] it was played")
	_check(p0.departure == &"" and m.players.has(p0), "...the character stays in the encounter")
	_check(p0.eth == 10, "...the ETH is paid all the same")
	var said: Array = lines[0][1] if not lines.is_empty() and lines[0][0] == p0 else []
	_check(
		said == [String(TranslationServer.translate("LOG_FLEE_QTE_FAILED"))],
		"...and the turn says so (%s)" % [said]
	)
	_check(m.history.previous_turn(p0) == null, "...(history sanity: one round only)")
	m.free()

	# Not enough ETH: no attempt, so no QTE.
	m = _encounter(&"fopin")
	p0 = m.players[0]
	p0.eth = 5
	fake.asked.clear()
	m.qte_runner = fake.play
	_flee(m, p0)
	await m.run(1)
	_check(fake.asked.is_empty() and p0.departure == &"", "without the ETH, there is no attempt")
	m.free()

	# A rival with the same talent never plays it, and gets away.
	m = _encounter(&"kalilk", &"fopin")
	var r0: EncounterIndividual = m.rivals[0]
	fake.verdict = false
	fake.asked.clear()
	m.qte_runner = fake.play
	_check(not m.flee_needs_qte(r0), "a rival's Run Away has no QTE")
	_flee(m, r0)
	await m.run(1)
	_check(fake.asked.is_empty(), "[rival] nobody is asked")
	_check(r0.departure == EncounterManager.FLED, "...and it runs away")
	m.free()

	# Run Away 2 (zuk) "doesn't require any QTE".
	m = _encounter(&"zuk")
	p0 = m.players[0]
	fake.asked.clear()
	m.qte_runner = fake.play
	_check(not m.flee_needs_qte(p0), "Run Away 2 has no QTE")
	_flee(m, p0)
	await m.run(1)
	_check(fake.asked.is_empty() and p0.departure == EncounterManager.FLED, "...it always succeeds")
	m.free()
