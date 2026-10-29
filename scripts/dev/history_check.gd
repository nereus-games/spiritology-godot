## Headless check of the encounter history — who did what to whom, round by round — and of the six
## abilities that read it: Halo Effect, Glorification, Moral Elevation, Catatonia, Self-Disclosure
## and Retroflection. Each one is played through real rounds, with someone it must touch and
## someone it must leave alone.
##
## Run with: Godot --headless --path . res://scenes/dev/history_check.tscn
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
	await _check_recording()
	await _check_halo_effect()
	await _check_glorification()
	await _check_moral_elevation()
	await _check_catatonia()
	await _check_self_disclosure()
	await _check_retroflection()
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
## (as indices into that list). Everyone passes until told otherwise, and has 20 ETH, so that
## nothing a check recovers is lost against the ceiling. The caller frees it.
func _encounter(order: Array = [0, 1, 2, 3]) -> EncounterManager:
	var all: Array = []
	for id in [&"kalilk", &"fliritus"]:
		all.append(EncounterManager.make_individual(id, true))
	for id in [&"ravbak", &"skorpis"]:
		all.append(EncounterManager.make_individual(id, false))
	var m := EncounterManager.new()
	m.setup([all[0], all[1]], [all[2], all[3]], 20261022)
	# Altruism is paid for with an object: the players own plenty, the rivals carry one each.
	m.inventory_view = func() -> Dictionary: return {&"notice": 99}
	for r in [all[2], all[3]]:
		r.carried_objects.append(&"notice")
	var ordered: Array = []
	for i in order:
		ordered.append(all[i])
	m.timeline.order = ordered
	for f in all:
		m.set_agent(f, Player.new())
		f.eth = 20
	return m


func _play(m: EncounterManager, who: EncounterIndividual, actions: Array) -> void:
	(m.agent_for(who) as Player).queued = actions


## Calls `fn(individual, manager)` each time `who` is asked what to do.
func _spy(m: EncounterManager, who: EncounterIndividual, fn: Callable) -> void:
	(m.agent_for(who) as Player).spy = fn


func _ability(id: StringName) -> AbilityData:
	return load(ABILITY_DIR + "%s.tres" % id)


## A plain attack with no script of its own: the generic damage effect, ten before modifiers.
func _hit(id := &"test_hit") -> AbilityData:
	var a := AbilityData.new()
	a.id = id
	a.energy = GameEnums.Energy.HEAT
	a.base_damage = 10
	a.tags = PackedStringArray(["damage"])
	return a


func _talk_to(target: EncounterIndividual) -> EncounterAction:
	return _kind(EncounterAction.Kind.TALK, target)


func _talks(_user, p0: EncounterIndividual) -> Array:
	return [_talk_to(p0), _talk_to(p0)]


func _talks_then_meditates(user: EncounterIndividual, p0: EncounterIndividual) -> Array:
	return [_talk_to(p0), _kind(EncounterAction.Kind.MEDITATE, user)]


func _hits_then_hits_again(_user, p0: EncounterIndividual) -> Array:
	return [_use(_hit(), p0), _use(_hit(), p0)]


func _hits_then_other(_user, p0: EncounterIndividual) -> Array:
	return [_use(_hit(), p0), _use(_hit(&"test_other"), p0)]


func _use(ability: AbilityData, target: EncounterIndividual) -> EncounterAction:
	return EncounterAction.use_ability(ability, [target])


func _kind(kind: EncounterAction.Kind, target: EncounterIndividual) -> EncounterAction:
	return EncounterAction.of_kind(kind, [target])


## The object provider of an encounter where every object is a tea drop.
func _tea_drop(_id: StringName) -> ObjectData:
	return load("res://data/objects/tea_drop.tres")


func _small() -> int:
	return BalanceData.current().damage(&"small")


## Every line of every turn, as [who, ability id (&"" when not one), lines], in order.
func _listen(m: EncounterManager) -> Array:
	var heard: Array = []
	m.turn_taken.connect(
		func(who, action, lines):
			var id: StringName = action.ability.id if action.ability != null else &""
			heard.append([who, id, lines])
	)
	return heard


## Whether `who`'s use of the ability said `line`.
func _said(heard: Array, who: EncounterIndividual, id: StringName, line: String) -> bool:
	for entry in heard:
		if entry[0] == who and entry[1] == id and entry[2].has(line):
			return true
	return false


func _examine_bonus_line(amount: int, who: EncounterIndividual) -> String:
	return String(TranslationServer.translate("LOG_EXAMINE_BOOST")) % [amount, who.display_name()]


## The energy the individual is exposing at its place in the order.
func _positional(m: EncounterManager, who: EncounterIndividual) -> GameEnums.Energy:
	return who.species.weakness_for(m.timeline.position_of(who))


func _other_energy(than: GameEnums.Energy) -> GameEnums.Energy:
	for e in [GameEnums.Energy.HEAT, GameEnums.Energy.FLUID, GameEnums.Energy.CRYSTAL]:
		if e != than:
			return e
	return GameEnums.Energy.NONE


# --------------------------------------------------------------------------
# The history itself
# --------------------------------------------------------------------------


func _check_recording() -> void:
	print("[recording]")
	var m := _encounter()
	var p0: EncounterIndividual = m.players[0]
	var r0: EncounterIndividual = m.rivals[0]
	var hit := _hit()
	_play(m, p0, [_use(hit, r0), _kind(EncounterAction.Kind.TALK, r0)])
	_play(m, r0, [_use(_ability(&"altruism"), r0)])
	var first_weakness := _positional(m, p0)
	await m.run(2)
	var h = m.history
	_check(h.round_number == 2, "the history follows the rounds")
	var now = h.turn_this_round(p0)
	var before = h.previous_turn(p0)
	_check(now != null and now.kind == EncounterAction.Kind.TALK, "this round's turn is the Talk")
	_check(before != null and before.ability_id == &"test_hit", "the previous one is the attack")
	_check(before != null and before.targets == [r0], "...with who it was aimed at")
	_check(before != null and before.damage_dealt > 0, "...and the damage it dealt")
	_check(before != null and before.weakness == first_weakness, "...and the weakness exposed")
	_check(h.times_used(p0, &"test_hit") == 1, "an ability is counted for the one who used it")
	_check(h.times_used(r0, &"test_hit") == 0, "...and not for anyone else")
	_check(h.abilities_used(p0) == 1, "a Talk is no ability")
	_check(h.abilities_used(r0) == 1, "...but an ability on oneself is")
	_check(h.hurt_recently(r0) and not h.hurt_recently(p0), "the damage is recorded on its victim")
	_check(not h.hurt_recently_by_teammate(r0), "...and a rival's damage is not a teammate's")
	_check(not h.side_helped_recently(false), "healing oneself is not help")
	m.free()


# --------------------------------------------------------------------------
# Halo Effect
# --------------------------------------------------------------------------


## Halo Effect used by p0 in round 2 (or in round 1 when `early`). In round 2 p0 stands third, after
## r0, which plays `r0_plays.call(r0, p0)`, one action a round; r1 passes both rounds; p1 has yet
## to act.
## The weakness of p1 and r1 is changed before p0 acts, and r0's too when `r0_changes`.
func _halo(early: bool, r0_plays: Callable, r0_changes: bool) -> Dictionary:
	var m := _encounter([2, 3, 0, 1])
	var p0: EncounterIndividual = m.players[0]
	var p1: EncounterIndividual = m.players[1]
	var r0: EncounterIndividual = m.rivals[0]
	var r1: EncounterIndividual = m.rivals[1]
	var halo := _ability(&"halo_effect")
	_play(
		m, p0, [_use(halo, p0)] if early else [_kind(EncounterAction.Kind.PASS, p0), _use(halo, p0)]
	)
	_play(m, r0, r0_plays.call(r0, p0))
	# p1 Talks both rounds but acts after p0, so it has done nothing yet when p0 looks; and it
	# has no weakness, either round.
	_play(m, p1, [_kind(EncounterAction.Kind.TALK, r0), _kind(EncounterAction.Kind.TALK, r0)])
	_spy(
		m,
		p1,
		func(f, mgr):
			if mgr.round_number == 1:
				f.override_weakness(GameEnums.Energy.NONE, f)
	)
	var changed := [r1] + ([r0] if r0_changes else [])
	_spy(
		m,
		p0,
		func(_f, mgr):
			if mgr.round_number == 2:
				p1.override_weakness(GameEnums.Energy.NONE, p1)
				for f in changed:
					f.override_weakness(_other_energy(_positional(mgr, f)), f)
	)
	var heard := _listen(m)
	var examined: Array = []
	m.ifp_earned.connect(
		func(_species, action, _forlorn, _effective, factor):
			if action == GameEnums.IfpAction.EXAMINE_RIVAL:
				examined.append(factor)
	)
	var eths := {}
	await m.run(1 if early else 2)
	for f in [p0, p1, r0, r1]:
		eths[f] = f.eth
	var out := {"m": m, "heard": heard, "eth": eths, "cost": halo.eth_cost(), "examined": examined}
	return out


func _check_halo_effect() -> void:
	print("[halo effect]")
	var halo := &"halo_effect"
	var r := await _halo(false, _talks, false)
	var m: EncounterManager = r["m"]
	var p0: EncounterIndividual = m.players[0]
	var p1: EncounterIndividual = m.players[1]
	var r0: EncounterIndividual = m.rivals[0]
	var r1: EncounterIndividual = m.rivals[1]
	_check(_positional(m, r0) != GameEnums.Energy.NONE, "[both] the rival has a weakness to repeat")
	_check(
		_said(r["heard"], p0, halo, _examine_bonus_line(4, r0)),
		"[both] same weakness and same action: a bonus per criterion"
	)
	_check(r["eth"][r0] == 20 + _small(), "[both] the individual picked recovers ETH")
	var step := BalanceData.current().examine_bonus_step
	_check(
		r["examined"].size() == 1 and is_equal_approx(r["examined"][0], 1.0 + 4 * step),
		"[both] the Examine of the rival yields its IFP times the bonus (%s)" % [r["examined"]]
	)
	_check(r["eth"][p0] == 20 - r["cost"] + _small(), "[both] ...and so does the user")
	_check(
		r["eth"][p1] == 20,
		"a teammate with no weakness, that has yet to act this round, is not picked"
	)
	_check(r["eth"][r1] == 20, "a rival that only passed, and whose weakness changed, is not")
	m.free()

	r = await _halo(false, _talks_then_meditates, false)
	m = r["m"]
	r0 = m.rivals[0]
	_check(
		_said(r["heard"], m.players[0], halo, _examine_bonus_line(2, r0)),
		"[weakness] same weakness only: one criterion"
	)
	_check(
		(
			r["examined"].size() == 1
			and is_equal_approx(
				r["examined"][0], 1.0 + 2 * BalanceData.current().examine_bonus_step
			)
		),
		"[weakness] ...and a smaller factor on the IFP (%s)" % [r["examined"]]
	)
	_check(
		r["eth"][r0] == 20 + BalanceData.current().meditate_eth + _small(),
		"[weakness] ...and it is the one that recovers"
	)
	m.free()

	r = await _halo(false, _talks, true)
	m = r["m"]
	r0 = m.rivals[0]
	_check(
		_said(r["heard"], m.players[0], halo, _examine_bonus_line(2, r0)),
		"[action] same action only: one criterion"
	)
	m.free()

	r = await _halo(false, _hits_then_hits_again, true)
	m = r["m"]
	_check(
		_said(r["heard"], m.players[0], halo, _examine_bonus_line(2, m.rivals[0])),
		"[ability] the same ability twice is the same action"
	)
	m.free()

	r = await _halo(false, _hits_then_other, true)
	m = r["m"]
	_check(
		not _said(r["heard"], m.players[0], halo, _examine_bonus_line(2, m.rivals[0])),
		"[ability] ...two different ones are not"
	)
	m.free()

	r = await _halo(true, _talks, false)
	m = r["m"]
	p0 = m.players[0]
	_check(
		_said(
			r["heard"], p0, halo, String(TranslationServer.translate("LOG_HISTORY_NOBODY_REPEATS"))
		),
		"[first turn] nobody can repeat itself yet"
	)
	_check(r["eth"][p0] == 20 - r["cost"], "[first turn] ...and nobody recovers anything")
	_check(r["eth"][m.rivals[0]] == 20, "[first turn] ...the rival included")
	m.free()


# --------------------------------------------------------------------------
# Glorification
# --------------------------------------------------------------------------


## p0 takes on r0's weakness; then `hitter` hits p0. Returns what p0's ETH was after
## Glorification and at the end.
func _glorify(hitter_index: int) -> Dictionary:
	var m := _encounter()
	var p0: EncounterIndividual = m.players[0]
	var glorification := _ability(&"glorification")
	_play(m, p0, [_use(glorification, m.rivals[0])])
	var hitter: EncounterIndividual = [m.rivals[0], m.rivals[1], m.players[1]][hitter_index]
	_play(m, hitter, [_use(_hit(), p0)])
	var seen := {}
	_spy(m, m.players[1], func(_f, _mgr): seen["after"] = p0.eth)
	# Read as the encounter ends: its individuals let go of each other right after.
	m.ended.connect(func(_result): seen["damager"] = p0.last_damager)
	await m.run(1)
	return {
		"m": m, "after": seen["after"], "damager": seen["damager"], "cost": glorification.eth_cost()
	}


func _check_glorification() -> void:
	print("[glorification]")
	var r := await _glorify(0)
	var m: EncounterManager = r["m"]
	var p0: EncounterIndividual = m.players[0]
	_check(r["after"] > 20 - r["cost"], "it gains ETH")
	_check(p0.den < p0.max_den, "the target did hurt it")
	_check(p0.eth == 20 - r["cost"], "...so it loses that ETH again")
	_check(r["damager"] == m.rivals[0], "...and not by being its own damager")
	_check(p0.reactions.is_empty(), "...once, after which nothing is armed")
	m.free()

	r = await _glorify(1)
	m = r["m"]
	p0 = m.players[0]
	_check(p0.den < p0.max_den, "[other rival] it was hurt")
	_check(
		p0.eth == r["after"], "[other rival] by someone it did not take the weakness of: no loss"
	)
	_check(p0.reactions.has(&"glorification"), "[other rival] ...and still waiting")
	m.free()

	r = await _glorify(2)
	m = r["m"]
	_check(m.players[0].eth == r["after"], "[teammate] a teammate that hurts it costs it nothing")
	m.free()

	# The weakness is the target's, whoever it then is: the teammate as target hurts it too.
	m = _encounter()
	var mate: EncounterIndividual = m.players[1]
	var user: EncounterIndividual = m.players[0]
	_play(m, user, [_use(_ability(&"glorification"), mate)])
	_play(m, mate, [_use(_hit(), user)])
	await m.run(1)
	_check(user.eth == 20 - _ability(&"glorification").eth_cost(), "[teammate target] same rule")
	m.free()


# --------------------------------------------------------------------------
# Moral Elevation
# --------------------------------------------------------------------------


func _check_moral_elevation() -> void:
	print("[moral elevation]")
	var moral := _ability(&"moral_elevation")
	var m := _encounter()
	var p0: EncounterIndividual = m.players[0]
	var r0: EncounterIndividual = m.rivals[0]
	_check(not m.can_play(p0, moral), "nothing has happened: not usable")
	_check(not m.can_play(r0, moral), "...for either side")
	p0.ability_ids.append(&"moral_elevation")
	_check(not m.usable_abilities(p0).has(moral), "...and the menu does not offer it")
	m.free()

	# Recovering by oneself is not being helped.
	m = _encounter([2, 0, 1, 3])
	p0 = m.players[0]
	r0 = m.rivals[0]
	_play(m, r0, [_kind(EncounterAction.Kind.MEDITATE, r0)])
	await m.run(1)
	_check(r0.eth > 20, "[self] the rival did recover")
	_check(not m.can_play(p0, moral), "[self] ...which is no help to it")
	m.free()

	# Help to a player is help to a rival, from the rivals' side only.
	m = _encounter()
	p0 = m.players[0]
	var p1: EncounterIndividual = m.players[1]
	r0 = m.rivals[0]
	p0.den = 50
	_play(m, p1, [_use(_ability(&"altruism"), p0)])
	await m.run(1)
	_check(p0.den > 50, "[teammate] DEN was healed")
	_check(m.can_play(r0, moral), "[teammate] a rival may use it: a player was helped")
	_check(not m.can_play(p0, moral), "[teammate] ...the player may not: its rivals were not")
	m.free()

	# Help that gains nothing is no help.
	m = _encounter()
	p0 = m.players[0]
	_play(m, m.players[1], [_use(_ability(&"altruism"), p0)])
	await m.run(1)
	_check(p0.den == p0.max_den, "[full] nothing to heal")
	_check(not m.can_play(m.rivals[0], moral), "[full] ...and so no help")
	m.free()

	# An object given to a rival, but not one used on oneself.
	m = _encounter()
	p0 = m.players[0]
	p1 = m.players[1]
	m.object_provider = _tea_drop
	var own := _kind(EncounterAction.Kind.USE_OBJECT, p1)
	own.object_id = &"tea_drop"
	_play(m, p1, [own])
	await m.run(1)
	_check(not m.can_play(p0, moral), "[object] one used on oneself is no gift")
	m.free()

	m = _encounter()
	m.object_provider = _tea_drop
	var gift := _kind(EncounterAction.Kind.USE_OBJECT, m.rivals[0])
	gift.object_id = &"tea_drop"
	_play(m, m.players[1], [gift])
	await m.run(1)
	_check(m.can_play(m.players[0], moral), "[object] one given to a rival is")
	_check(not m.can_play(m.rivals[0], moral), "[object] ...and only to its opponents")
	m.free()

	# Recently: this round and the one before.
	m = _encounter()
	p0 = m.players[0]
	_play(m, m.players[1], [_use(_ability(&"self_disclosure"), m.players[1])])
	await m.run(1)
	_check(m.can_play(p0, moral), "[window] help given this round counts")
	m.history.begin_round(2)
	_check(m.can_play(p0, moral), "[window] ...and still in the next")
	m.history.begin_round(3)
	_check(not m.can_play(p0, moral), "[window] ...but not after that")
	m.free()

	# Used, then.
	m = _encounter()
	p0 = m.players[0]
	_play(m, m.players[1], [_use(_ability(&"self_disclosure"), m.players[1])])
	_play(m, p0, [_kind(EncounterAction.Kind.PASS, p0), _use(moral, p0)])
	await m.run(2)
	_check(p0.eth == p0.max_eth, "[used] ETH is refilled")
	_check(p0.weakness_locked, "[used] ...and the weakness locked")
	_check(
		p0.active_weakness(m.timeline.position_of(p0)) == GameEnums.Energy.NONE,
		"[used] ...after being removed"
	)
	m.free()

	# Used anyway.
	m = _encounter()
	p0 = m.players[0]
	_play(m, p0, [_use(moral, p0)])
	var heard := _listen(m)
	await m.run(1)
	_check(p0.eth == 20 - moral.eth_cost(), "[forced] it costs its ETH, and nothing refills it")
	_check(not p0.weakness_locked, "[forced] ...nothing is locked")
	_check(
		_said(
			heard,
			p0,
			&"moral_elevation",
			String(TranslationServer.translate("LOG_CONDITION_UNMET"))
		),
		"[forced] ...and the log says why"
	)
	m.free()


# --------------------------------------------------------------------------
# Catatonia
# --------------------------------------------------------------------------


## The Examine bonus Catatonia granted p0, or -1. `order` as for `_encounter`; `damage` is a list
## of [round, hitter index, victim index]; p0 uses Catatonia in `round_used`.
func _catatonia(order: Array, damage: Array, round_used: int) -> int:
	var m := _encounter(order)
	var all := [m.players[0], m.players[1], m.rivals[0], m.rivals[1]]
	var p0: EncounterIndividual = all[0]
	var plays := {}
	for f in all:
		plays[f] = []
		for _i in round_used:
			plays[f].append(_kind(EncounterAction.Kind.PASS, f))
	for d in damage:
		plays[all[d[1]]][d[0] - 1] = _use(_hit(), all[d[2]])
	plays[p0][round_used - 1] = _use(_ability(&"catatonia"), p0)
	for f in all:
		_play(m, f, plays[f])
	var heard := _listen(m)
	await m.run(round_used)
	var seen := -1
	for n in [2, 4, 6]:
		if _said(heard, p0, &"catatonia", _examine_bonus_line(n, p0)):
			seen = n
	m.free()
	return seen


func _check_catatonia() -> void:
	print("[catatonia]")
	var rivals_first := [2, 0, 1, 3]
	_check(
		await _catatonia(rivals_first, [[1, 2, 1]], 1) == 2,
		"[nobody] damage to someone else changes nothing"
	)
	_check(
		await _catatonia(rivals_first, [[1, 2, 0]], 1) == 4,
		"[rival] damage this turn: a bigger bonus"
	)
	_check(
		await _catatonia([1, 0, 2, 3], [[1, 1, 0]], 1) == 6,
		"[teammate] ...larger still from a teammate"
	)
	_check(
		await _catatonia(rivals_first, [[1, 2, 0]], 2) == 4,
		"[previous] damage on the previous turn too"
	)
	_check(
		await _catatonia(rivals_first, [[1, 2, 0]], 3) == 2, "[old] ...but not the one before that"
	)
	_check(
		await _catatonia([1, 0, 2, 3], [[1, 1, 0]], 3) == 2,
		"[old teammate] ...a teammate's included"
	)
	_check(
		await _catatonia(rivals_first, [[1, 0, 0]], 2) == 4,
		"[self] damage it did itself is damage, but no teammate's"
	)


# --------------------------------------------------------------------------
# Self-Disclosure
# --------------------------------------------------------------------------


func _check_self_disclosure() -> void:
	print("[self-disclosure]")
	var disclosure := _ability(&"self_disclosure")
	# p0 has used one ability when it uses this one: the pool is two shares of ETH, between four.
	var m := _encounter()
	var p0: EncounterIndividual = m.players[0]
	_play(m, p0, [_use(_hit(), m.rivals[0]), _use(disclosure, p0)])
	var snap := {}
	_spy(
		m,
		p0,
		func(_f, mgr):
			if mgr.round_number == 2:
				for f in mgr.players + mgr.rivals:
					snap[f] = f.eth
	)
	await m.run(2)
	var share := floori(float(2 * _small()) / 4)
	_check(share > 0, "the share is something")
	_check(p0.eth == snap[p0] - disclosure.eth_cost() + share, "the user gets a share")
	for f in [m.players[1], m.rivals[0], m.rivals[1]]:
		_check(f.eth == snap[f] + share, "...as does everyone else (%s)" % f.species_id())
	m.free()

	# Used first, with a dissolved rival and a rival that used an ability before: the pool is one
	# share of ETH, between the three standing.
	m = _encounter([2, 0, 1, 3])
	p0 = m.players[0]
	var r0: EncounterIndividual = m.rivals[0]
	var r1: EncounterIndividual = m.rivals[1]
	r1.den = 0
	_play(m, r0, [_use(_hit(), m.players[1])])
	_play(m, p0, [_use(disclosure, p0)])
	snap = {}
	var p1: EncounterIndividual = m.players[1]
	_spy(
		m,
		p0,
		func(_f, _mgr):
			for f in [p0, p1, r0]:
				snap[f] = f.eth
	)
	await m.run(1)
	share = floori(float(_small()) / 3)
	_check(share > 0, "[alone] the share is something")
	_check(m.history.abilities_used(r0) == 1, "[alone] the rival did use one")
	_check(
		p0.eth == snap[p0] - disclosure.eth_cost() + share, "[alone] the pool counts the user's own"
	)
	_check(r0.eth == snap[r0] + share, "[alone] ...shared with a rival")
	_check(p1.eth == snap[p1] + share, "[alone] ...and a teammate")
	_check(r1.eth == 20, "[alone] ...but not with a dissolved one")
	m.free()


# --------------------------------------------------------------------------
# Retroflection
# --------------------------------------------------------------------------


## What damage of `base` before modifiers does to `who` when it strikes itself: the same species
## and the same spiricosm, plus the weakness if the energy is the one it exposes.
func _userinflicted(m: EncounterManager, who: EncounterIndividual, base: int) -> int:
	var energy := _ability(&"retroflection").energy
	var conditions := 2 + (1 if energy == _positional(m, who) else 0)
	return ceili(base * (1.0 + BalanceData.current().modifier_per_condition * conditions))


func _check_retroflection() -> void:
	print("[retroflection]")
	var retro := _ability(&"retroflection")
	var m := _encounter()
	var p0: EncounterIndividual = m.players[0]
	var r0: EncounterIndividual = m.rivals[0]
	_play(m, p0, [_use(retro, p0), _use(retro, p0)])
	_play(m, r0, [_kind(EncounterAction.Kind.PASS, r0), _use(retro, r0)])
	var snap := {}
	_spy(m, p0, func(f, mgr): snap[mgr.round_number] = f.den)
	_spy(m, r0, func(f, mgr): snap[-mgr.round_number] = f.den)
	var mini := BalanceData.current().damage(&"mini")
	var normal := BalanceData.current().damage(&"normal")
	var expected_p0_first := _userinflicted(m, p0, mini)
	var expected_p0_later := _userinflicted(m, p0, normal)
	var expected_r0_first := _userinflicted(m, r0, mini)
	await m.run(2)
	_check(snap[1] - snap[2] == expected_p0_first, "the first use costs mini")
	_check(snap[2] - p0.den == expected_p0_later, "...the next one normal")
	_check(expected_p0_later > expected_p0_first, "...which is more")
	_check(snap[-2] - r0.den == expected_r0_first, "someone else's first use is its own first")
	_check(p0.eth == p0.max_eth, "ETH is refilled all the same")
	m.free()
