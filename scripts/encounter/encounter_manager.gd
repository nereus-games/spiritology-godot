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
signal ended(result: StringName)  ## &"victory" / &"defeat" / &"timeout"

## IFP earned by a player action on a rival — Examine, Talk, or dissolving it.
##
## The manager deliberately knows nothing of [GameSession]. Reaching for an autoload would
## tie it to a running game and cost it the ability to be tested on its own, so it
## announces what happened and the encounter UI relays it to
## [method GameSession.award_ifp].
signal ifp_earned(
	species_id: StringName, action: GameEnums.IfpAction, is_forlorn: bool, dialogue_effective: bool
)

## An object was spent by a Use / Give action — "Objects are all consumable items". The UI
## removes it from the inventory, for the same reason as [signal ifp_earned].
signal object_consumed(object_id: StringName)

## Turns an object slug into [ObjectData]. Injected by the UI, again so that the manager
## needs no autoload.
var object_provider: Callable = Callable()

const ABILITY_DIR := "res://data/abilities/"

## Resolves a talent to its script. Reached by preload rather than by name: neither
## [TalentCatalog] nor [TalentScript] declares a `class_name`, because only the editor
## regenerates the global class cache and this game is launched from the command line.
const TalentCatalog := preload("res://scripts/encounter/talents/talent_catalog.gd")

var players: Array = []
var rivals: Array = []
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


## Prepares the encounter. Resets the agents, so set any [UiAgent] AFTER calling this.
func setup(
	player_individuals: Array, rival_individuals: Array, seed: int = 0, completed: Dictionary = {}
) -> void:
	players = player_individuals
	rivals = rival_individuals
	completed_species = completed
	rng.seed = seed
	result = &""
	_agents.clear()
	timeline = EncounterTimeline.new()
	# "Turn order is defined at random when the encounter begins". Not cosmetic: position
	# decides which weakness each individual exposes, so a fixed order would freeze the
	# weaknesses too. Drawn from the seeded rng above — different every encounter, and
	# reproducible for a given seed.
	timeline.setup(players + rivals, rng)
	_collect_talents()


## Builds a [TalentScript] for every individual carrying a talent.
##
## Two individuals of the same species on one side stack the talent, which is what `stacks`
## carries — counted on the bearer's own side, and held at 1 for talents the doc does not
## make stackable.
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
	return encounter_abilities(individual).filter(func(a): return individual.can_use(a))


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
	# AFTER the signal, so listeners still see the full state: break the reference cycles
	# between individuals (see EncounterIndividual.release_cross_references).
	for f in players + rivals:
		f.release_cross_references()
	return res


func _begin_round() -> void:
	# Exposed because the doc wants the current round shown permanently in the log,
	# whatever the player has scrolled to.
	round_number += 1
	# One random energy for the whole round, shared by every Random/Variable ability.
	_round_energy = _random_energy()
	for f in timeline.order:
		f.clear_turn_state()


func _take_turn(individual: EncounterIndividual) -> void:
	# The agent may be synchronous or a coroutine; `await` covers both.
	@warning_ignore("redundant_await")
	var action: EncounterAction = await agent_for(individual).decide(individual, self)
	if action == null:
		encounter_log.append(_tr("LOG_NO_ACTION") % individual.display_name())
		return
	var dissolved_before := rivals.filter(func(f): return f.is_dissolved())
	_resolve_action(individual, action)
	if individual.is_player:
		_award_dissolutions(dissolved_before)


## "Use Ability – upon dissolving rival": rivals dissolved by THIS player turn yield their
## IFP. One brought down by another rival — through reflection or redirection —
## yields nothing, which is why the caller guards on `individual.is_player`.
func _award_dissolutions(dissolved_before: Array) -> void:
	for r in rivals:
		if r.is_dissolved() and not dissolved_before.has(r):
			ifp_earned.emit(
				r.species_id(), GameEnums.IfpAction.DISSOLVE_RIVAL, _is_forlorn(r), true
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
		GameEnums.ObjectEffect.FLEE_ENCOUNTER:
			# "allows to Run away from an encounter". Fleeing itself — teleporting 3-5 tiles
			# away, with a 50 % chance the rival disappears — belongs to exploration, which
			# does not handle it yet.
			lines.append(
				(
					_tr("LOG_OBJECT_FLEE_GIVEN" if given else "LOG_OBJECT_FLEE_USED")
					% tr(obj.name_key())
				)
			)
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


## Run Away, put in the menu by a talent (run_away_2, slick_merchant). Actually leaving
## needs the exploration-side teleport, which is unbuilt — hence the stub.
##
## slick_merchant costs 10 ETH and a QTE that can fail; run_away_2 is free and certain.
## Those conditions belong to the talents, and will be enforced once fleeing works.
func _resolve_flee(individual: EncounterIndividual, action: EncounterAction) -> void:
	_emit_turn(individual, action, [_tr("LOG_FLEE_ATTEMPT")])


## Meditate: "character recovers X ETH; damage +Y % until next turn".
##
## The bonus applies to damage DEALT — a design decision, the doc does not say — and lands
## on the meditating individual's NEXT turn, the only moment it could strike anyway.
## See EncounterIndividual.grant_next_turn_damage_bonus for why that is done in two steps.
func _resolve_meditate(individual: EncounterIndividual, action: EncounterAction) -> void:
	var before := individual.eth
	var balance := BalanceData.current()
	individual.recover_eth(balance.meditate_eth)
	individual.grant_next_turn_damage_bonus(balance.meditate_damage_bonus)
	_emit_turn(
		individual,
		action,
		[
			(
				_tr("LOG_MEDITATE")
				% [before, individual.eth, roundi(balance.meditate_damage_bonus * 100.0)]
			)
		]
	)


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
	var effective := rng.randf() < chance
	ifp_earned.emit(
		target.species_id(), GameEnums.IfpAction.TALK_RIVAL, _is_forlorn(target), effective
	)
	var verdict := _tr("LOG_DIALOGUE_EFFECTIVE" if effective else "LOG_DIALOGUE_INEFFECTIVE")
	_emit_turn(individual, action, [_tr("LOG_TALK") % [target.display_name(), verdict]])
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
	ifp_earned.emit(
		target.species_id(), GameEnums.IfpAction.EXAMINE_RIVAL, _is_forlorn(target), true
	)
	# Recon Glide (ravbak) raises the bearer's Examine yield by 10 %. How much information
	# an Examine yields is not modelled at all, so we start from 1.0 and log the factor:
	# observable, but with nothing yet to act on.
	var info := 1.0
	for t in _talents:
		if t.owner == individual:
			info = t.modify_examine_info(self, target, info)
	# TODO: "reveals objects they carry" — rivals carry none, and the examined rival's
	# Talk/Challenge reaction is unwritten.
	# TODO: Coal Vetch — two Examines on the same rival, or one ability, should give some
	# chance of an agent appearing mid-encounter. No such system exists.
	var suffix := _tr("LOG_EXAMINE_INFO_FACTOR") % info if not is_equal_approx(info, 1.0) else ""
	_emit_turn(individual, action, [_tr("LOG_EXAMINE") % [target.display_name(), suffix]])


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
	individual.pay_eth(ability.eth_cost())
	var ctx := EncounterContext.new()
	ctx.ability = ability
	ctx.user = individual
	ctx.targets = action.targets
	ctx.all_individuals = timeline.living()
	ctx.timeline = timeline
	ctx.rng = rng
	ctx.completed_species = completed_species
	ctx.resolved_energy = _round_energy
	EffectCatalog.script_for(ability).execute(ctx)
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


func _check_end() -> StringName:
	if rivals.all(func(f): return f.is_dissolved()):
		return &"victory"
	if players.all(func(f): return f.is_dissolved()):
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
