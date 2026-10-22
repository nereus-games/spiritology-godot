## Runs an encounter: turn order, action resolution, and how it ends.
##
## Wires the effect system ([EffectCatalog]) onto the combat state ([EncounterIndividual],
## [EncounterTimeline]). The model is per ROUND: everyone acts once, per-turn state is
## wiped at the start, pending reordering is applied at the end.
##
## The manager does not DECIDE. Each turn it asks the individual's [EncounterAgent]. By
## default every individual has an [AutoAgent], so [method run] resolves the whole encounter
## in one go without ever suspending — that is what makes it testable headless. Putting a
## [UiAgent] on an individual makes its turns playable; the loop itself does not change.
class_name EncounterManager
extends Node

## `lines` is the log its effects produced.
signal turn_taken(
	individual: EncounterIndividual, action: EncounterAction, lines: PackedStringArray
)
## An ability that was watching for something reacted to it. `lines` is what it did. Announced
## separately from [signal turn_taken] because the one who reacts is not the one whose turn it is.
signal reaction_noted(reactor: EncounterIndividual, ability: AbilityData, lines: PackedStringArray)
## How the encounter ended — see [method _check_end] for when each one applies:
## &"victory", &"defeat", &"fled", &"pacified", &"rivals_fled", &"timeout".
signal ended(result: StringName)

## An individual left the encounter before its end. `reason` is [constant FLED] or
## [constant PACIFIED].
signal departed(individual: EncounterIndividual, reason: StringName)

## IFP earned by a player action on a rival — Examine, Talk, or dissolving it.
##
## The manager deliberately knows nothing of [GameSession]. Reaching for an autoload would
## tie it to a running game and cost it the ability to be tested on its own, so it
## announces what happened and the encounter UI relays it to
## [method GameSession.award_ifp]. `yield_factor` scales the amount the table gives — 1.0 unless
## a next-turn modifier acts on it (Hardening's Talk penalty).
signal ifp_earned(
	species_id: StringName,
	action: GameEnums.IfpAction,
	is_forlorn: bool,
	dialogue_effective: bool,
	yield_factor: float
)

## An object was spent by a Use / Give action — "Objects are all consumable items". The UI
## removes it from the inventory, for the same reason as [signal ifp_earned].
signal object_consumed(object_id: StringName)

## Turns an object slug into [ObjectData]. Injected by the UI, again so that the manager
## needs no autoload.
var object_provider: Callable = Callable()

## [bridges] Reveals one hidden thing on the exploration map the encounter was entered from, and
## returns whether it found anything. Injected like [member object_provider], for the same
## reason: the manager must not reach the dungeon. Invalid in a harness without a map.
var map_reveal: Callable = Callable()

## [bridges] Whether the LAST Talk of the encounter was effective. False until one is resolved.
var last_talk_effective := false

const ABILITY_DIR := "res://data/abilities/"

## Why an individual left: it ran away (Run Away, a smoke bomb, Ghosting)...
const FLED := &"fled"
## ...or it was talked out of the encounter. Nothing decides that yet — the dialogue system
## does not exist — but the way out is built: see [method pacify].
const PACIFIED := &"pacified"

## Resolves a talent to its script. Reached by preload rather than by name: neither
## [TalentCatalog] nor [TalentScript] declares a `class_name`, because only the editor
## regenerates the global class cache and this game is launched from the command line.
const TalentCatalog := preload("res://scripts/encounter/talents/talent_catalog.gd")
const EncounterEvent := preload("res://scripts/encounter/encounter_event.gd")
const EncounterHistory := preload("res://scripts/encounter/encounter_history.gd")
const ExamineYield := preload("res://scripts/encounter/effects/examine_yield.gd")

## The individuals still IN the encounter, dissolved ones included. One who leaves is taken out
## of these lists and out of the turn order, so that no targeting rule, no talent and no
## ability has to learn about departures.
var players: Array = []
var rivals: Array = []
## Everyone who took part, in the order [method setup] received them — departed included.
## What [method rival_report] reads.
var all_players: Array = []
var all_rivals: Array = []
var timeline: EncounterTimeline
var rng := RandomNumberGenerator.new()
## Species whose encyclopaedia page is complete — one of the damage conditions.
var completed_species: Dictionary = {}

## How the encounter ended, &"" while it is still running.
##
## [method run] is a coroutine, so its return value is only reachable with `await`.
## Callers that cannot wait read this field, or listen to [signal ended].
var result := &""

## Current round, 1-based; 0 before the encounter starts.
var round_number := 0

var encounter_log: PackedStringArray = PackedStringArray()

## Per-individual agents. Anyone absent from here uses [member default_agent].
var _agents: Dictionary = {}
var default_agent: EncounterAgent = AutoAgent.new()

## One [TalentScript] per individual that actually carries a talent. The manager calls their
## hooks at the points of the loop that matter: start and end, a resolved Talk, a
## single-use ability spent.
var _talents: Array = []

var _round_energy := GameEnums.Energy.NONE

## The damage the action being resolved dealt, for the reactions that care whether it dealt any.
var _action_damage := 0

## Who did what to whom so far, turn by turn. Read by the abilities, through their context.
var history := EncounterHistory.new()

## The teammate that may refuse to act (PSY above rung 4), and whether its next action is the
## one it always refuses. Armed by [method enable_refusal]; nobody refuses by default.
var _refusing: EncounterIndividual = null
var _refuse_next := false


## Prepares the encounter. Resets the agents, so set any [UiAgent] AFTER calling this.
func setup(
	player_individuals: Array, rival_individuals: Array, seed: int = 0, completed: Dictionary = {}
) -> void:
	players = player_individuals.duplicate()
	rivals = rival_individuals.duplicate()
	all_players = player_individuals.duplicate()
	all_rivals = rival_individuals.duplicate()
	completed_species = completed
	rng.seed = seed
	result = &""
	_refusing = null
	_refuse_next = false
	_agents.clear()
	timeline = EncounterTimeline.new()
	# "Turn order is defined at random when the encounter begins". Not cosmetic: position
	# decides which weakness each individual exposes, so a fixed order would freeze the
	# weaknesses too. Drawn from the seeded rng above — different every encounter, and
	# reproducible for a given seed.
	timeline.setup(players + rivals, rng)
	history = EncounterHistory.new()
	_collect_talents()


## Builds a [TalentScript] for every individual carrying a talent.
##
## Two individuals of the same species on one side stack the talent, which is what `stacks`
## carries — counted on the bearer's own side, and held at 1 for talents the doc does not
## make stackable.
## Arms the teammate's refusals. `first_action` makes its very next action a refusal; after
## that, each action is refused with [member BalanceData.psy_teammate_refusal_chance], drawn
## from [member rng]. The manager knows no autoload, so the caller decides whether PSY allows it.
func enable_refusal(teammate: EncounterIndividual, first_action: bool) -> void:
	_refusing = teammate
	_refuse_next = first_action


func _collect_talents() -> void:
	_talents.clear()
	for f in players + rivals:
		if f.species == null or f.species.talent == &"":
			continue
		var td := _load_talent(f.species.talent)
		if td == null:
			continue
		var stacks := 1
		if td.stacks_in_duo:
			stacks = allies_of(f).filter(func(a): return a.species_id() == f.species_id()).size()
		_talents.append(TalentCatalog.script_for(td, f, stacks))


## Loads a [TalentData] by slug. Talents share `data/abilities/` with the abilities but are
## a different type, so `as TalentData` yields null for an ability slug — which is exactly
## what should happen.
func _load_talent(slug: StringName) -> TalentData:
	if slug == &"":
		return null
	var path := ABILITY_DIR + String(slug) + ".tres"
	return load(path) as TalentData if ResourceLoader.exists(path) else null


## Every line this class logs goes through here, so that none of them is ever written out
## in one language. See the LOG_* block in `translations/en.po`.
##
## A thin wrapper over `tr()` on purpose: [EncounterContext] and [TalentScript] are
## RefCounted and have no `tr()`, so they carry the same `_tr` over
## `TranslationServer.translate`. One name to grep for, across all three.
func _tr(key: String) -> String:
	return tr(key)


## [bridges] Asks the map to reveal one hidden thing ([member map_reveal]). False when there is
## no map or nothing was left to reveal.
func reveal_on_map() -> bool:
	return map_reveal.is_valid() and bool(map_reveal.call())


## A log line from a talent rather than from a turn. Prefixed so the two are told apart.
func note_talent(line: String) -> void:
	encounter_log.append(_tr("LOG_LINE_TALENT") % line)


## Builds an individual from a species slug.
static func make_individual(species_id: StringName, is_player: bool) -> EncounterIndividual:
	var sp: SpeciesData = load("res://data/species/%s.tres" % species_id)
	if sp == null:
		push_error("[EncounterManager] unknown species: %s" % species_id)
		return null
	return EncounterIndividual.new(sp, is_player)


# --- Agents ---


## Gives an individual its own agent, in place of [member default_agent].
func set_agent(individual: EncounterIndividual, agent: EncounterAgent) -> void:
	_agents[individual] = agent


func agent_for(individual: EncounterIndividual) -> EncounterAgent:
	return _agents.get(individual, default_agent)


# --- What the agents may choose from ---


## Encounter abilities still in the individual's repertoire, INCLUDING the ones it cannot
## afford: the doc wants unusable actions greyed out, not hidden.
## See [method usable_abilities] for the ones actually playable.
func encounter_abilities(individual: EncounterIndividual) -> Array:
	var out: Array = []
	for aid in individual.ability_ids:
		var a := resolve_ability(aid)
		if a != null and a.type == GameEnums.AbilityType.ENCOUNTER and not individual.is_spent(a):
			out.append(a)
	return out


## What the individual can play right now. Drives the auto policy, and tells the menu when a
## turn is lost for want of anything to do.
func usable_abilities(individual: EncounterIndividual) -> Array:
	return encounter_abilities(individual).filter(func(a): return can_play(individual, a))


## Playable right now: neither spent nor unaffordable, and the ability's own condition is met —
## see [method AbilityScript.is_usable].
func can_play(individual: EncounterIndividual, ability: AbilityData) -> bool:
	if not individual.can_use(ability):
		return false
	return EffectCatalog.script_for(ability).is_usable(_make_context(individual, ability, []))


## Whether the ability is aimed at opponents. A SCAFFOLD built on the tags, standing in
## until the doc describes targeting ability by ability.
func is_offensive(ability: AbilityData) -> bool:
	return (
		ability.tags.has("damage")
		or ability.tags.has("ETH loss")
		or ability.tags.has("change weakness")
		or ability.tags.has("limit actions")
	)


## Legal targets: opponents still standing if the ability is offensive, otherwise itself.
##
## One rule, shared by [AutoAgent] and the player's menu, so the two cannot drift. Abilities
## with global reach (Tumult) widen their own scope at execution time through
## [member EncounterContext.all_individuals] and are not concerned by this.
func candidate_targets(individual: EncounterIndividual, ability: AbilityData) -> Array:
	if is_offensive(ability):
		return opponents_of(individual).filter(func(f): return not f.is_dissolved())
	return [individual]


func opponents_of(individual: EncounterIndividual) -> Array:
	return rivals if individual.is_player else players


## Opponents still standing — the targets of Talk, Examine and Give Object.
func living_opponents(individual: EncounterIndividual) -> Array:
	return opponents_of(individual).filter(func(f): return not f.is_dissolved())


## The base actions offered to an individual, AFTER its talents have had their say.
##
## Starts at ABILITY, TALK, EXAMINE. A talent may remove one and add FLEE or STEAL —
## run_away_2, steal and slick_merchant all do, through
## [method TalentScript.modify_menu]. An action a talent removed is ABSENT rather than
## greyed: the talent replaces it, it does not forbid it.
func menu_kinds(individual: EncounterIndividual) -> Array:
	var kinds: Array = [
		EncounterAction.Kind.ABILITY, EncounterAction.Kind.TALK, EncounterAction.Kind.EXAMINE
	]
	for t in _talents:
		if t.owner == individual:
			t.modify_menu(self, kinds)
	return kinds


## Who this individual may Talk to: living rivals, plus its own teammate if a talent allows it
## (Serene Waves, where talking to the teammate heals them). Never itself.
func talk_targets(individual: EncounterIndividual) -> Array:
	var targets := living_opponents(individual)
	for t in _talents:
		if t.owner == individual and t.allows_ally_talk(self):
			for a in allies_of(individual):
				if a != individual and not a.is_dissolved() and not targets.has(a):
					targets.append(a)
			break
	return targets


func allies_of(individual: EncounterIndividual) -> Array:
	return players if individual.is_player else rivals


func resolve_ability(aid: StringName) -> AbilityData:
	var path := ABILITY_DIR + String(aid) + ".tres"
	return load(path) as AbilityData if ResourceLoader.exists(path) else null


# --- The loop ---


## Starts the loop WITHOUT waiting for it, for callers that react to [signal ended] rather
## than to a return value — the encounter UI, which has to hand control back to its scene.
##
## GDScript refuses to call a coroutine without `await`; the dynamic call below is the way
## around that, deliberately isolated here. Prefer `await run()` when you can wait.
func start(max_rounds: int = 30) -> void:
	run.call(max_rounds)


## Runs the encounter to its end. A coroutine: it suspends on turns driven by a [UiAgent],
## and never suspends at all when every agent is automatic.
func run(max_rounds: int = 30) -> StringName:
	for t in _talents:
		t.on_encounter_start(self)
	for _r in max_rounds:
		_begin_round()
		for individual in timeline.order.duplicate():
			if individual.has_left():
				continue
			# Before the skip below: a dissolved individual's effects still have to run out.
			_start_turn_of(individual)
			if individual.is_dissolved():
				continue
			await _take_turn(individual)
			var res := _check_end()
			if res != &"":
				return _finish(res)
		timeline.apply_pending()
	return _finish(&"timeout")


func _finish(res: StringName) -> StringName:
	result = res
	# End-of-encounter talents run BEFORE `ended` is emitted — Restore heals the duo, and the
	# UI writes DEN/ETH back to GameSession on that signal, so it has to see the healed
	# state, not the state before.
	for t in _talents:
		t.on_encounter_end(self, res)
	ended.emit(res)
	# AFTER the signal, so listeners still see the full state.
	_release_individuals()
	return res


## Also released when the manager is freed, because an encounter can be torn down before
## [method _finish] ever runs: the game quit while the player is choosing, or a dev harness
## that screenshots the moment of choice. Doing it only in [method _finish] leaked every
## cycle of an unfinished encounter — including an individual hurt by its own ability, which
## is its own [member EncounterIndividual.last_damager].
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_release_individuals()


## Breaks the reference cycles between individuals (see
## [method EncounterIndividual.release_cross_references]). Safe to call more than once.
func _release_individuals() -> void:
	for f in all_players + all_rivals:
		f.release_cross_references()


func _begin_round() -> void:
	# Exposed because the doc wants the current round shown permanently in the log,
	# whatever the player has scrolled to.
	round_number += 1
	history.begin_round(round_number)
	# One random energy for the whole round, shared by every Random/Variable ability.
	_round_energy = _random_energy()


## `individual`'s turn begins: whatever effects it anchored count down one turn — see
## [EncounterIndividual] on how long an effect lasts.
func _start_turn_of(individual: EncounterIndividual) -> void:
	for f in all_players + all_rivals:
		f.on_turn_start(individual)
	_run_recurring(individual)


func _take_turn(individual: EncounterIndividual) -> void:
	# The agent may be synchronous or a coroutine; `await` covers both.
	@warning_ignore("redundant_await")
	var action: EncounterAction = await agent_for(individual).decide(individual, self)
	if action == null:
		encounter_log.append(_tr("LOG_NO_ACTION") % individual.display_name())
		return
	if individual == _refusing and _teammate_refuses():
		_emit_turn(
			individual,
			EncounterAction.of_kind(EncounterAction.Kind.PASS, [individual]),
			[_tr("LOG_TEAMMATE_REFUSES")]
		)
		return
	var dissolved_before := rivals.filter(func(f): return f.is_dissolved())
	_action_damage = 0
	var weakness_then := individual.active_weakness(timeline.position_of(individual))
	_resolve_action(individual, action)
	history.record_turn(individual, action, _action_damage, weakness_then)
	_react_to_action(individual, action)
	if individual.is_player:
		_award_dissolutions(dissolved_before)


## Does the teammate refuse the action it just chose? The first one it is asked for, once armed
## so, always; every later one by chance. The draw is skipped for the forced refusal, so a given
## seed stays reproducible either way.
func _teammate_refuses() -> bool:
	if _refuse_next:
		_refuse_next = false
		return true
	return rng.randf() < BalanceData.current().psy_teammate_refusal_chance


## "Use Ability – upon dissolving rival": rivals dissolved by THIS player turn yield their
## IFP. One brought down by another rival — through reflection or redirection —
## yields nothing, which is why the caller guards on `individual.is_player`.
func _award_dissolutions(dissolved_before: Array) -> void:
	for r in rivals:
		if r.is_dissolved() and not dissolved_before.has(r):
			ifp_earned.emit(
				r.species_id(), GameEnums.IfpAction.DISSOLVE_RIVAL, _is_forlorn(r), true, 1.0
			)


func _resolve_action(individual: EncounterIndividual, action: EncounterAction) -> void:
	match action.kind:
		EncounterAction.Kind.ABILITY:
			_resolve_ability(individual, action)
		EncounterAction.Kind.MEDITATE:
			_resolve_meditate(individual, action)
		EncounterAction.Kind.TALK:
			_resolve_talk(individual, action)
		EncounterAction.Kind.EXAMINE:
			_resolve_examine(individual, action)
		EncounterAction.Kind.USE_OBJECT:
			_resolve_object(individual, action)
		EncounterAction.Kind.STEAL:
			_resolve_steal(individual, action)
		EncounterAction.Kind.FLEE:
			_resolve_flee(individual, action)
		EncounterAction.Kind.PASS:
			# The doc's "…" action: passes the turn WITHOUT giving up your place.
			_emit_turn(individual, action, [_tr("LOG_PASS")])
		_:
			_emit_turn(individual, action, [_tr("LOG_ACTION_UNRESOLVED") % action.label()])


## Use / Give Object: "select object and target (can be a rival); Use if target is player
## character, Give if target is rival".
##
## The object is spent EITHER WAY — "Objects are all consumable items" — including when the
## effect does nothing in an encounter. Giving one to a rival is itself the useful gesture.
##
## Removing it from the inventory does not happen here; the manager announces
## [signal object_consumed] and the UI relays it.
func _resolve_object(individual: EncounterIndividual, action: EncounterAction) -> void:
	var obj: ObjectData = (
		object_provider.call(action.object_id) if object_provider.is_valid() else null
	)
	if obj == null:
		_emit_turn(individual, action, [_tr("LOG_OBJECT_NOT_FOUND") % action.object_id])
		return
	var target := _first_target(action)
	if target == null:
		target = individual
	var given := not target.is_player
	object_consumed.emit(action.object_id)
	var lines: Array = []
	match obj.effect:
		GameEnums.ObjectEffect.HEAL_DEN:
			# "gives Y DEN to a target" — Y is a placeholder in the doc, so magnitude stays
			# 0 and the balance value stands in.
			var amount: int = (
				obj.magnitude if obj.magnitude > 0 else BalanceData.current().object_heal_den
			)
			var before := target.den
			target.recover_den(amount)
			lines.append(
				(
					_tr("LOG_OBJECT_HEAL_GIVEN" if given else "LOG_OBJECT_HEAL_USED")
					% [tr(obj.name_key()), target.display_name(), before, target.den]
				)
			)
		GameEnums.ObjectEffect.FLEE_ENCOUNTER when not given:
			# "allows to Run away from an encounter" — for the character it is used on, like Run
			# Away: the other one stays in. Given to a rival it is only a gift, and falls through
			# to the default below.
			lines.append(_tr("LOG_OBJECT_FLEE_USED") % [tr(obj.name_key()), target.display_name()])
			_emit_turn(individual, action, lines)
			withdraw(target, FLED)
			return
		_:
			# NONE, CURE_POISON, DISGUISE, DIG, AVOID_PURSUIT do nothing IN AN ENCOUNTER.
			# Notice is explicitly "no effect" and exists to be given away; the rest belong
			# to exploration — crumbly ground, poison, pursuit.
			lines.append(
				(
					_tr("LOG_OBJECT_GIVEN" if given else "LOG_OBJECT_USED")
					% [tr(obj.name_key()), target.display_name()]
				)
			)
	_emit_turn(individual, action, lines)


## Steal, from granop's talent: "takes an object from the target, but has a risk of a
## member of The Coal Vetch appearing; if present, Steal has a 50 % chance of failing".
##
## A stub, because stealing supposes rivals CARRY objects — nothing says which — and the
## Coal Vetch does not exist. The action is routed and logged anyway, so the chain from
## menu to resolution is whole the day those systems arrive.
func _resolve_steal(individual: EncounterIndividual, action: EncounterAction) -> void:
	var target := _first_target(action)
	if target == null:
		_emit_turn(individual, action, [_tr("LOG_STEAL_NO_TARGET")])
		return
	_emit_turn(individual, action, [_tr("LOG_STEAL") % target.display_name()])


## Run Away, put in the menu by a talent (run_away_2, slick_merchant). Only the character who
## runs leaves: while its teammate is still in, the encounter goes on. It ends as a flight once
## no character is left in it.
##
## What happens next is exploration's business: the duo lands 3-5 tiles away, and the rivals
## still in the encounter stay where they were. The encounter only records who left.
##
## slick_merchant charges 10 ETH, through [method flee_cost].
## ## TODO: slick_merchant's QTE, which can make the attempt fail. There is no QTE system; until
## there is, its Run Away always succeeds.
func _resolve_flee(individual: EncounterIndividual, action: EncounterAction) -> void:
	var cost := flee_cost(individual)
	if individual.eth < cost:
		_emit_turn(individual, action, [_tr("LOG_FLEE_NO_ETH") % cost])
		return
	individual.pay_eth(cost)
	_emit_turn(individual, action, [_tr("LOG_FLEE")])
	withdraw(individual, FLED)


## What running away costs this individual in ETH — 0 unless one of its talents charges for
## it. The menu greys Run Away out when it cannot be paid.
func flee_cost(individual: EncounterIndividual) -> int:
	var cost := 0
	for t in _talents:
		if t.owner == individual:
			cost = maxi(cost, t.flee_eth_cost(self))
	return cost


# --- Leaving before the end ---


## Takes an individual out of the encounter: out of its side, out of the turn order. It keeps
## its DEN and ETH, and [method rival_report] tells exploration how it left.
##
## Does not end the encounter by itself — the loop checks for that after every turn, which is
## where a departure happens.
func withdraw(individual: EncounterIndividual, reason: StringName) -> void:
	if individual == null or individual.has_left() or individual.is_dissolved():
		return
	if not (players.has(individual) or rivals.has(individual)):
		return
	individual.departure = reason
	players.erase(individual)
	rivals.erase(individual)
	timeline.remove(individual)
	# It will have no next turn, so what was waiting for one ends now.
	for f in all_players + all_rivals:
		f.expire_anchored_to(individual)
	departed.emit(individual, reason)


## The way out through dialogue: the individual leaves the encounter without being dissolved.
##
## The entry point the dialogue system will call once it exists. Nothing in the game decides
## that a rival is pacified yet — the design doc gives no rule, and none is invented here. The
## encounter UI has a debug key that calls this, so that the route can be walked end to end.
func pacify(individual: EncounterIndividual) -> void:
	withdraw(individual, PACIFIED)


## How each rival came out of the encounter, in the order [method setup] received them. This
## is what exploration writes back onto the group on the map.
##
## `outcome` is &"dissolved", [constant FLED], [constant PACIFIED], or &"stayed" for a rival
## still in the encounter when it ended — after a defeat, a flight or a timeout.
func rival_report() -> Array:
	var out: Array = []
	for f in all_rivals:
		var outcome := &"stayed"
		if f.is_dissolved():
			outcome = &"dissolved"
		elif f.has_left():
			outcome = f.departure
		var entry := {
			"species_id": f.species_id(),
			"den": f.den,
			"max_den": f.max_den,
			"eth": f.eth,
			"max_eth": f.max_eth,
			"outcome": outcome,
		}
		out.append(entry)
	return out


## Meditate: "character recovers X ETH; damage +Y % until next turn".
##
## The bonus applies to damage DEALT — a design decision, the doc does not say — and lands
## on the meditating individual's NEXT turn, the only moment it could strike anyway.
func _resolve_meditate(individual: EncounterIndividual, action: EncounterAction) -> void:
	var before := individual.eth
	var balance := BalanceData.current()
	# Catatonia: each step it left adds the per-condition step to both the ETH and the bonus.
	var boost := 1.0 + individual.consume_meditate_boost() * balance.modifier_per_condition
	var damage_bonus: float = balance.meditate_damage_bonus * boost
	individual.recover_eth(ceili(balance.meditate_eth * boost))
	individual.grant_next_turn_damage_bonus(damage_bonus)
	var lines: Array = [
		_tr("LOG_MEDITATE") % [before, individual.eth, roundi(damage_bonus * 100.0)]
	]
	lines.append_array(_shake_off_recurring(individual))
	_emit_turn(individual, action, lines)


## Talk: "initiate dialogue with rival". Earns IFP only if the dialogue is
## effective.
func _resolve_talk(individual: EncounterIndividual, action: EncounterAction) -> void:
	var target := _first_target(action)
	if target == null:
		_emit_turn(individual, action, [_tr("LOG_TALK_NO_TARGET")])
		return
	# Whether a dialogue "works" is an admitted PLACEHOLDER. The doc conditions Talk's
	# reward on an effective dialogue without ever giving the rule, and its dialogue drafts
	# make it depend on objects given to the rival — which does not exist. So we fall back
	# on the species' talker_chance, which actually describes how likely the RIVAL is to
	# open a conversation. A proxy, not the rule. See docs/roadmap.md.
	var chance: float = target.species.talker_chance if target.species else 0.0
	# Talents on the speaker's side may adjust it — Slick Merchant adds 15 % over the first
	# three turns, applied to that same proxy.
	var speaker_team := allies_of(individual)
	for t in _talents:
		if speaker_team.has(t.owner):
			chance = t.modify_talk_chance(self, individual, target, chance)
	# The target was fled from above the first PSY rung: its chance is a share lower, whatever
	# the talents did, for as long as PSY stays above that rung. Relative, and applied last.
	if GameSession.psy_above(1):
		chance *= 1.0 - clampf(target.talk_chance_malus, 0.0, 1.0)
	var effective := rng.randf() < chance
	last_talk_effective = effective  # [bridges]
	var talk_yield := _talk_yield(individual, effective)
	# Only a player's Talk earns IFP; a rival talking to a player character earns none.
	if individual.is_player:
		ifp_earned.emit(
			target.species_id(), talk_yield[0], _is_forlorn(target), effective, talk_yield[1]
		)
	var verdict := _tr("LOG_DIALOGUE_EFFECTIVE" if effective else "LOG_DIALOGUE_INEFFECTIVE")
	var lines: Array = [_tr("LOG_TALK") % [target.display_name(), verdict]]
	lines.append_array(talk_yield[2])
	_emit_turn(individual, action, lines)
	# Talents that react to a resolved Talk: Serene Waves heals the teammate, Slick Merchant
	# gives the rival the speaker's own weakness.
	for t in _talents:
		if speaker_team.has(t.owner):
			t.on_talk_resolved(self, individual, target, effective)


## Examine: "gets info on rival; reveals objects they carry; rival may react with Talk or
## Challenge". Revealing objects and the rival's reaction both need systems that do not
## exist; the IFP, at least, are awarded — Examine "works all the time".
func _resolve_examine(individual: EncounterIndividual, action: EncounterAction) -> void:
	var target := _first_target(action)
	if target == null:
		_emit_turn(individual, action, [_tr("LOG_EXAMINE_NO_TARGET")])
		return
	# The yield is the table's amount times the info factor: the bonuses on the examiner
	# (Priming, Catatonia) and its talents (Recon Glide's 10 %). GameSession rounds it.
	var info := examine_factor(individual, target)
	ifp_earned.emit(
		target.species_id(), GameEnums.IfpAction.EXAMINE_RIVAL, _is_forlorn(target), true, info
	)
	# TODO: "reveals objects they carry" — rivals carry none, and the examined rival's
	# Talk/Challenge reaction is unwritten.
	# TODO: Coal Vetch — two Examines on the same rival, or one ability, should give some
	# chance of an agent appearing mid-encounter. No such system exists.
	var suffix := _tr("LOG_EXAMINE_INFO_FACTOR") % info if not is_equal_approx(info, 1.0) else ""
	_emit_turn(individual, action, [_tr("LOG_EXAMINE") % [target.display_name(), suffix]])


## The factor on the IFP of an Examine of `target` by `individual`: its info bonus points, plus
## `extra_points` an ability puts on this one Examine (Halo Effect), as
## [method ExamineYield.factor_for] values them, times what each of its talents makes of it
## (Reconnaissance Glide).
func examine_factor(
	individual: EncounterIndividual, target: EncounterIndividual, extra_points := 0
) -> float:
	var info := ExamineYield.factor_for(individual.examine_bonus_points + extra_points)
	for t in _talents:
		if t.owner == individual:
			info = t.modify_examine_info(self, target, info)
	return info


## The Examines an ability made of other individuals (Halo Effect). Only a player character's
## Examine of a rival earns IFP.
func _carry_out_examines(individual: EncounterIndividual, ctx: EncounterContext) -> void:
	if not individual.is_player:
		return
	for entry in ctx.examines:
		var target: EncounterIndividual = entry[0]
		if not rivals.has(target) or target.is_dissolved():
			continue
		ifp_earned.emit(
			target.species_id(),
			GameEnums.IfpAction.EXAMINE_RIVAL,
			_is_forlorn(target),
			true,
			examine_factor(individual, target, entry[1])
		)


# --- Next-turn modifiers ---


## What the modifiers on a speaker make of a Talk's IFP: [the action the yield is looked up
## under, the factor on it, the log lines saying so]. Active Listening is spent by the Talk it
## changes whether or not the dialogue worked; the yield is still earned only by an effective
## one, so an ineffective Talk stays [constant GameEnums.IfpAction.TALK_RIVAL] and gets nothing.
func _talk_yield(individual: EncounterIndividual, effective: bool) -> Array:
	var ifp_action := GameEnums.IfpAction.TALK_RIVAL
	var lines: Array = []
	if individual.consume_talk_as_examine():
		lines.append(_tr("LOG_TALK_YIELDS_EXAMINE"))
		if effective:
			ifp_action = GameEnums.IfpAction.EXAMINE_RIVAL
	var factor := individual.talk_info_factor
	if not is_equal_approx(factor, 1.0):
		lines.append(_tr("LOG_TALK_INFO_PENALIZED") % factor)
	return [ifp_action, factor, lines]


## Whether this individual is its species' Forlorn variant.
## TODO: Forlorn variants are not modelled on the individual at all — [SpeciesData] carries
## only a Forlorn ability and sprite. Until they are, the higher Forlorn IFP can
## never be earned.
func _is_forlorn(_individual: EncounterIndividual) -> bool:
	return false


func _first_target(action: EncounterAction) -> EncounterIndividual:
	for t in action.targets:
		if t is EncounterIndividual and not t.is_dissolved():
			return t
	return null


func _emit_turn(individual: EncounterIndividual, action: EncounterAction, lines: Array) -> void:
	var packed := PackedStringArray(lines)
	for l in packed:
		encounter_log.append(_tr("LOG_LINE") % [individual.display_name(), l])
	turn_taken.emit(individual, action, packed)


func _resolve_ability(individual: EncounterIndividual, action: EncounterAction) -> void:
	if action.ability == null:
		_emit_turn(individual, action, [_tr("LOG_ABILITY_NOT_FOUND")])
		return
	var ability := action.ability
	# Which targets have their exposed weakness struck — captured BEFORE the effect runs,
	# since the effect may change weaknesses on its way through. Feeds Examine Weakness.
	var touched := _weakness_touched_targets(individual, ability, action.targets)
	# Paid BEFORE the effect, so that an ability which restores ETH cannot refund itself.
	# Agents only ever offer what is affordable; pay_eth clamps at 0 regardless.
	var free := individual.consume_free_ability()
	if not free:
		individual.pay_eth(ability.eth_cost())
	var ctx := _make_context(individual, ability, action.targets)
	if free:
		ctx.note(_tr("LOG_ABILITY_FREE"))
	EffectCatalog.script_for(ability).execute(ctx)
	_action_damage = ctx.damage_dealt
	_carry_out_examines(individual, ctx)
	individual.mark_used(ability)
	# Reuse (jézal) can hand a single-use ability back.
	if ability.single_use:
		for t in _talents:
			if t.owner == individual and t.wants_reuse(self, individual, ability):
				individual.clear_used(ability)
				note_talent(_tr("LOG_TALENT_REUSE") % [individual.display_name(), ability.id])
				break
	# Examine Weakness (gélmi): information gleaned whenever a weakness is struck.
	for target in touched:
		for t in _talents:
			t.on_weakness_touched(self, individual, target, ability)
	for l in ctx.log_lines:
		encounter_log.append(_tr("LOG_LINE_ABILITY") % [individual.display_name(), ability.id, l])
	turn_taken.emit(individual, action, ctx.log_lines)
	_announce_reactions(ctx.reactions_noted)
	# Departures happen at the END of the turn — Opening up Closing's "the user flees at the end
	# of the turn" — so that the rest of the effect still sees everyone.
	for f in ctx.departures:
		withdraw(f, FLED)


## The context an effect runs in, for `individual` using `ability` on `targets`.
func _make_context(
	individual: EncounterIndividual, ability: AbilityData, targets: Array
) -> EncounterContext:
	var ctx := EncounterContext.new()
	ctx.ability = ability
	ctx.user = individual
	ctx.targets = targets
	ctx.all_individuals = timeline.living()
	ctx.timeline = timeline
	ctx.rng = rng
	ctx.completed_species = completed_species
	ctx.resolved_energy = _round_energy
	ctx.history = history
	return ctx


## The recurring effects on `individual` act, at the start of its turn. Announced the way a
## reaction is, under the bearer's name.
func _run_recurring(individual: EncounterIndividual) -> void:
	if individual.is_dissolved() or individual.recurring.is_empty():
		return
	var noted: Array = []
	for entry in individual.recurring.values():
		var applied: AbilityData = entry[0]
		var source := instance_from_id(entry[1]) as EncounterIndividual
		var ctx := _make_context(source if source != null else individual, applied, [individual])
		ctx.in_reaction = true
		EffectCatalog.script_for(applied).recur(ctx)
		if not ctx.log_lines.is_empty():
			noted.append([individual, applied, ctx.log_lines])
	_announce_reactions(noted)


## Meditating: the recurring effects on `individual` that can be shaken off end. Returns the lines
## to add to the turn.
func _shake_off_recurring(individual: EncounterIndividual) -> Array:
	var lines: Array = []
	for aid in individual.recurring.keys():
		var applied: AbilityData = individual.recurring[aid][0]
		var ctx := _make_context(individual, applied, [individual])
		if not EffectCatalog.script_for(applied).on_meditated(ctx):
			continue
		individual.recurring.erase(aid)
		lines.append(
			_tr("LOG_RECURRING_SHAKEN_OFF") % [individual.display_name(), _tr(applied.name_key())]
		)
		lines.append_array(ctx.log_lines)
	return lines


## `individual`'s action has been resolved: whoever is watching is told, whatever the action was.
## Damage is told on its own, as it is dealt — see [method EncounterContext.deal_damage].
func _react_to_action(individual: EncounterIndividual, action: EncounterAction) -> void:
	var ctx := _make_context(individual, null, action.targets)
	ctx.fire(EncounterEvent.acted(individual, action, _action_damage))
	_announce_reactions(ctx.reactions_noted)


func _announce_reactions(noted: Array) -> void:
	for entry in noted:
		var reactor: EncounterIndividual = entry[0]
		var ability: AbilityData = entry[1]
		var lines: PackedStringArray = entry[2]
		for l in lines:
			encounter_log.append(_tr("LOG_LINE_ABILITY") % [reactor.display_name(), ability.id, l])
		reaction_noted.emit(reactor, ability, lines)


## Targets whose exposed weakness matches the ability's effective energy.
##
## Best-effort: Random and Variable resolve through [member _round_energy], as
## [EncounterContext] does, but an energy override applied inside an effect is not seen.
## Enough for Examine Weakness, whose own effect is a stub anyway.
func _weakness_touched_targets(
	_user: EncounterIndividual, ability: AbilityData, targets: Array
) -> Array:
	var energy := ability.energy if ability else GameEnums.Energy.NONE
	if energy == GameEnums.Energy.RANDOM or energy == GameEnums.Energy.VARIABLE:
		energy = _round_energy
	if energy == GameEnums.Energy.NONE:
		return []
	var out: Array = []
	for target in targets:
		if target is EncounterIndividual and not target.is_dissolved():
			if energy == target.active_weakness(timeline.position_of(target)):
				out.append(target)
	return out


## The encounter is over once one side has nobody standing left IN it — dissolved, or gone.
##
## - &"victory": every rival was dissolved. The only outcome that feeds the FDE counter.
## - &"pacified": the rivals are all gone, and at least one was talked out of it.
## - &"rivals_fled": the rivals are all gone, at least one by running away, none pacified.
## - &"fled": the player characters are all gone, and at least one ran away.
## - &"defeat": the player characters were all dissolved.
##
## Rivals are looked at first, as they always were: a turn that empties both sides counts
## for the player.
func _check_end() -> StringName:
	if rivals.all(func(f): return f.is_dissolved()):
		if all_rivals.all(func(f): return f.is_dissolved()):
			return &"victory"
		if all_rivals.any(func(f): return f.departure == PACIFIED):
			return &"pacified"
		return &"rivals_fled"
	if players.all(func(f): return f.is_dissolved()):
		if all_players.any(func(f): return f.departure == FLED):
			return &"fled"
		return &"defeat"
	return &""


func _random_energy() -> GameEnums.Energy:
	var pool := [
		GameEnums.Energy.HEAT,
		GameEnums.Energy.FLUID,
		GameEnums.Energy.CRYSTAL,
		GameEnums.Energy.ARCANE,
		GameEnums.Energy.TOXIC
	]
	return pool[rng.randi_range(0, pool.size() - 1)]
