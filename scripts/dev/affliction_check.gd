## Headless check of the afflictions carried into an encounter: poison takes DEN once a round from
## every individual that holds it, however many hold it; disarray turns an action into one of
## another kind, one move per action; both are spent on the object the map holds, so that what is
## left comes back to exploration; a group on the map and the player's node hand them over.
##
## Run with: Godot --headless --path . res://scenes/dev/affliction_check.tscn
## As a start scene rather than --script; see geometry_check.gd.
extends Node

const ENCOUNTER := preload("res://scenes/encounter/encounter.tscn")
const AfflictionState := preload("res://scripts/exploration/mechanisms/affliction_state.gd")
const RivalMember := preload("res://scripts/exploration/rival_member.gd")
const RIVAL_SCENE := preload("res://scenes/exploration/rival/rival.tscn")
const SEED := 20261029

var _fails: Array[String] = []


## Plays queued actions, then passes.
class Scripted:
	extends EncounterAgent
	var queued: Array = []

	func decide(individual: EncounterIndividual, _manager: EncounterManager) -> EncounterAction:
		if not queued.is_empty():
			return queued.pop_front()
		return EncounterAction.of_kind(EncounterAction.Kind.PASS, [individual])


class FakePlayer:
	extends Node
	var affliction


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
	await _check_poison()
	await _check_disarray()
	await _check_hand_over()
	print("")
	if _fails.is_empty():
		print("ALL OK")
	else:
		print("FAILURES: %s" % [_fails])
	get_tree().quit(0 if _fails.is_empty() else 1)


## Two players against one rival, everyone passing, so that only the afflictions act.
func _field(seed: int = SEED) -> Dictionary:
	var p1 := EncounterManager.make_individual(&"kalilk", true)
	var p2 := EncounterManager.make_individual(&"fliritus", true)
	var r := EncounterManager.make_individual(&"ravbak", false)
	var m := EncounterManager.new()
	m.setup([p1, p2], [r], seed)
	for f in [p1, p2, r]:
		m.set_agent(f, Scripted.new())
	return {"m": m, "p1": p1, "p2": p2, "r": r}


func _poison(turns: int, per_turn: int) -> AfflictionState:
	var aff := AfflictionState.new(1)
	aff.add_poison(turns, per_turn)
	return aff


func _check_poison() -> void:
	print("[poison]")
	var f := _field()
	var aff := _poison(2, 5)
	f.p1.affliction = aff
	f.p2.affliction = aff
	var notes: Array = []
	f.m.affliction_noted.connect(func(who, line): notes.append([who, line]))
	var den1: int = f.p1.den
	var den2: int = f.p2.den
	await f.m.run(1)
	_check(f.p1.den == den1 - 5 and f.p2.den == den2 - 5, "a round takes 5 DEN off each of the duo")
	_check(aff.poison_turns == 1, "...once, however many hold it, using up one turn of poison")
	_check(notes.size() == 2, "...and says so for each of them")
	f.m.free()

	f = _field()
	aff = _poison(2, 5)
	f.p1.affliction = aff
	f.p2.affliction = aff
	den1 = f.p1.den
	await f.m.run(5)
	_check(f.p1.den == den1 - 10 and aff.poison_turns == 0, "it stops with its last turn")
	_check(not aff.has_poison(), "...which the map sees too, the object being the same")
	f.m.free()

	# A poisoned rival, of its own group's affliction.
	f = _field()
	aff = _poison(1, 7)
	f.r.affliction = aff
	var rden: int = f.r.den
	await f.m.run(1)
	_check(f.r.den == rden - 7 and f.p1.den == f.p1.max_den, "a poisoned rival loses DEN alone")
	f.m.free()

	# Fatal poison ends the encounter at once rather than at the next turn.
	f = _field()
	aff = _poison(3, 500)
	f.r.affliction = aff
	var res: StringName = await f.m.run(5)
	_check(res == &"victory" and f.m.round_number == 1, "poison that dissolves the last rival wins")
	f.m.free()

	f = _field()
	aff = _poison(3, 500)
	f.p1.affliction = aff
	f.p2.affliction = aff
	res = await f.m.run(5)
	_check(res == &"defeat", "...and that dissolves the duo loses")
	f.m.free()

	# Not afflicted: nothing changes.
	f = _field()
	await f.m.run(2)
	_check(f.p1.den == f.p1.max_den and f.r.den == f.r.max_den, "with no affliction, nothing is lost")
	f.m.free()


func _disarray(moves: Array) -> AfflictionState:
	var aff := AfflictionState.new(1)
	var queue: Array[bool] = []
	for b in moves:
		queue.append(b)
	aff._disarray_queue = queue
	return aff


func _kinds_played(m: EncounterManager) -> Array:
	var kinds: Array = []
	m.turn_taken.connect(
		func(who, action, _lines):
			if who.is_player:
				kinds.append(action.kind)
	)
	return kinds


func _check_disarray() -> void:
	print("[disarray]")
	var examine := EncounterAction.Kind.EXAMINE
	var f := _field()
	var aff := _disarray([true, false, true])
	f.p1.affliction = aff
	f.p2.affliction = aff
	var notes: Array = []
	f.m.affliction_noted.connect(func(_who, line): notes.append(line))
	var kinds := _kinds_played(f.m)
	f.m.timeline.order = [f.p1, f.p2, f.r]
	var agent1: Scripted = f.m.agent_for(f.p1)
	var agent2: Scripted = f.m.agent_for(f.p2)
	agent1.queued = [EncounterAction.of_kind(examine, [f.r]), EncounterAction.of_kind(examine, [f.r])]
	agent2.queued = [EncounterAction.of_kind(examine, [f.r])]
	await f.m.run(2)
	# Round 1: p1 (deflected), p2 (not). Round 2: p1 (deflected).
	_check(kinds.size() >= 3, "three player turns were played")
	if kinds.size() >= 3:
		_check(kinds[0] != examine, "a deflected action is of another kind")
		_check(kinds[1] == examine, "an action that is not deflected stands")
		_check(kinds[2] != examine, "...and the queue is shared by the duo, move by move")
	_check(aff.remaining_disarray() == 0, "every action spent a move of the one the map holds")
	_check(notes.size() == 2, "each deflection is announced")
	f.m.free()

	# A pass costs no move.
	f = _field()
	aff = _disarray([true])
	f.p1.affliction = aff
	await f.m.run(1)
	_check(aff.remaining_disarray() == 1, "passing spends no move")
	f.m.free()

	# Never an object, never Flee or Steal, whatever the seed.
	var odd := 0
	var other_kinds := {}
	for seed in 60:
		f = _field(seed)
		aff = _disarray([true])
		f.p1.affliction = aff
		f.m.timeline.order = [f.p1, f.p2, f.r]
		(f.m.agent_for(f.p1) as Scripted).queued = [EncounterAction.of_kind(examine, [f.r])]
		var played := _kinds_played(f.m)
		await f.m.run(1)
		other_kinds[played[0]] = true
		if played[0] in [EncounterAction.Kind.USE_OBJECT, EncounterAction.Kind.FLEE]:
			odd += 1
		if played[0] in [EncounterAction.Kind.STEAL, examine]:
			odd += 1
		f.m.free()
	_check(odd == 0, "a stumble is never an object, a flight, a theft or the same action")
	_check(other_kinds.size() >= 2, "...and varies between Ability, Talk and Meditate")

	# A rival stumbles between the two things it does.
	f = _field()
	aff = _disarray([true])
	f.r.affliction = aff
	var rival_kinds: Array = []
	f.m.turn_taken.connect(
		func(who, action, _lines):
			if not who.is_player:
				rival_kinds.append(action.kind)
	)
	f.m.timeline.order = [f.r, f.p1, f.p2]
	(f.m.agent_for(f.r) as Scripted).queued = [
		EncounterAction.of_kind(EncounterAction.Kind.MEDITATE, [f.r])
	]
	await f.m.run(1)
	_check(
		rival_kinds.size() == 1 and rival_kinds[0] == EncounterAction.Kind.ABILITY,
		"a rival that would Meditate uses an ability instead"
	)
	f.m.free()

	# Without disarray the random stream is untouched: same seed, same encounter.
	var a := _field()
	var b := _field()
	await a.m.run(3)
	await b.m.run(3)
	_check(a.m.rng.randi() == b.m.rng.randi(), "no affliction leaves the replay as it was")
	a.m.free()
	b.m.free()


func _check_hand_over() -> void:
	print("[from the map]")
	var group = RIVAL_SCENE.instantiate()
	group.members.append(RivalMember.new(&"ravbak", 60, 40))
	group.members.append(RivalMember.new(&"skorpis", 60, 40))
	_check(not group.encounter_states()[0].has("affliction"), "a healthy group hands nothing over")
	group.affliction.add_poison(3, 4)
	var states: Array = group.encounter_states()
	_check(
		states[0]["affliction"] == group.affliction and states[1]["affliction"] == group.affliction,
		"an afflicted group hands every member its own affliction object"
	)
	group.free()

	var node := FakePlayer.new()
	node.affliction = _poison(2, 3)
	node.add_to_group("player")
	add_child(node)
	var ui := ENCOUNTER.instantiate()
	get_tree().root.add_child(ui)
	var aff := _poison(2, 6)
	ui.begin(["kalilk", "fliritus"], ["ravbak", "skorpis"], {}, [{"affliction": aff}, {}], SEED)
	for _i in 10:
		await get_tree().process_frame
	var m: EncounterManager = ui._manager
	_check(
		(
			m.all_players[0].affliction == node.affliction
			and m.all_players[1].affliction == node.affliction
		),
		"the duo enters with the affliction of the player on the map"
	)
	_check(ui.player_poisoned, "...and the PSY poison rule still reads it")
	_check(
		m.all_rivals[0].affliction == aff and m.all_rivals[1].affliction == null,
		"a rival enters with its own and an unafflicted one with none"
	)
	# Poison running out in the encounter lifts the PSY rule with it.
	node.affliction.poison_turns = 0
	ui._on_affliction_noted(m.all_players[0], "x")
	_check(not ui.player_poisoned, "poison that ran out no longer forbids Meditate")
	ui.queue_free()
	node.queue_free()
	await get_tree().process_frame
