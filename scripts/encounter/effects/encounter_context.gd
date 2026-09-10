## What an ability's effect is given to work with.
##
## The single seam between the effects — 111 small scripts — and the state of the
## encounter: the individuals, the turn order, the UI. Effects never touch that state
## directly; they ask this, and this applies the rules.
##
## Which is where the rules live: the per-condition damage modifiers, the weakness a
## position exposes, mitigation and immunity, redirection. Written once here rather than
## 111 times over there.
class_name EncounterContext
extends RefCounted


## Damage added per condition met — weakness struck, shared Spiricosm, completed page,
## same species. Conditions add up before being applied. Tuned in `data/balance.tres`.
static func _modifier_per_condition() -> float:
	return BalanceData.current().modifier_per_condition


## Asks the UI for something only it can do — Tumult moving its elements, Anodyne Excess
## hiding the rivals' stats.
signal ui_requested(kind: StringName, data: Dictionary)

var ability: AbilityData
var user  ## The EncounterIndividual using the ability
var targets: Array = []  ## The EncounterIndividuals it is aimed at
var all_individuals: Array = []  ## Everyone, for the encounter-wide effects (Tumult)
var timeline: EncounterTimeline
var rng: RandomNumberGenerator

## The ability's energy for this turn, with Random and Variable already resolved.
var resolved_energy := GameEnums.Energy.NONE
## Species whose encyclopaedia page is complete — one of the damage conditions.
var completed_species: Dictionary = {}
## Forced energy, for abilities that take on the user's own weakness. NONE means off.
var energy_override := GameEnums.Energy.NONE

## What this effect did, in readable lines. Reaches the player through the encounter log.
var log_lines: PackedStringArray = PackedStringArray()


func note(line: String) -> void:
	log_lines.append(line)


# --- Damage: modifiers, mitigation, redirection ---


func deal_damage(target, base_amount: int) -> void:
	if base_amount <= 0:
		return
	var victim = target
	if victim is EncounterIndividual and victim.redirect_to != null:
		victim = victim.redirect_to
		victim.redirect_to = null
	if victim is EncounterIndividual and victim.is_immune_to(_effective_energy()):
		note(_tr("LOG_IMMUNE") % _name(victim))
		return
	var amount := _apply_modifiers(victim, base_amount)
	if victim is EncounterIndividual:
		amount = ceili(
			(
				amount
				* victim.next_damage_factor
				* victim.energy_damage_factor.get(_effective_energy(), 1.0)
			)
		)
		victim.next_damage_factor = 1.0
		victim.apply_damage(amount)
		if user is EncounterIndividual and amount > 0:
			victim.last_damager = user
			if victim.reflect_to_attacker and user != victim:
				user.apply_damage(amount)  # Reflux: as much goes back to the attacker
	note(_tr("LOG_DAMAGE") % [amount, _name(victim)])


## Conditions add up, then the user's own outgoing bonus if it meditated last turn, and
## the result is rounded up.
func _apply_modifiers(target, base_amount: int) -> int:
	if not (target is EncounterIndividual) or not (user is EncounterIndividual):
		return base_amount
	var conditions := 0
	var energy := _effective_energy()
	var pos: GameEnums.TurnPosition = (
		timeline.position_of(target) if timeline else GameEnums.TurnPosition.MIDDLE
	)
	if energy != GameEnums.Energy.NONE and energy == target.active_weakness(pos):
		conditions += 1
	if user.species and target.species and user.species.spiricosm == target.species.spiricosm:
		conditions += 1
	if completed_species.has(target.species_id()):
		conditions += 1
	if user.species_id() == target.species_id():
		conditions += 1
	return ceili(
		base_amount * (1.0 + _modifier_per_condition() * conditions + user.outgoing_damage_bonus)
	)


func _effective_energy() -> GameEnums.Energy:
	if energy_override != GameEnums.Energy.NONE:
		return energy_override
	if ability and ability.energy in [GameEnums.Energy.RANDOM, GameEnums.Energy.VARIABLE]:
		return resolved_energy
	return ability.energy if ability else GameEnums.Energy.NONE


# --- Other mutations ---


func drain_eth(target, amount: int) -> void:
	if target is EncounterIndividual:
		target.drain_eth(amount)
		if user is EncounterIndividual:
			target.last_damager = user
	note(_tr("LOG_ETH_DRAINED") % [_name(target), amount])


func recover_den(target, amount: int) -> void:
	if target is EncounterIndividual:
		target.recover_den(amount)
	note(_tr("LOG_DEN_RECOVERED") % [_name(target), amount])


func recover_eth(target, amount: int) -> void:
	if target is EncounterIndividual:
		target.recover_eth(amount)
	note(_tr("LOG_ETH_RECOVERED") % [_name(target), amount])


## Swaps the target's exposed weakness for another, at random — never the same one.
func change_weakness(target) -> void:
	if target is EncounterIndividual:
		target.override_weakness(
			_random_energy_other_than(
				target.active_weakness(
					timeline.position_of(target) if timeline else GameEnums.TurnPosition.MIDDLE
				)
			)
		)
	note(_tr("LOG_WEAKNESS_CHANGED") % _name(target))


## Multiplies the target's next incoming damage; 0 is immunity.
func modify_damage(target, factor: float) -> void:
	if target is EncounterIndividual:
		target.next_damage_factor = factor
	note(_tr("LOG_NEXT_DAMAGE_FACTOR") % [_name(target), factor])


func redirect_next_damage(from_target, to_target) -> void:
	if from_target is EncounterIndividual and to_target is EncounterIndividual:
		from_target.redirect_to = to_target
	note(_tr("LOG_DAMAGE_REDIRECTED") % [_name(from_target), _name(to_target)])


# Stubs, waiting on systems that do not exist: actions, dialogue, information gain.
# They log what would have happened so the mechanic is at least visible. See
# docs/roadmap.md.
func limit_actions(target, amount: int) -> void:
	note(_tr("LOG_ACTIONS_LOST") % [_name(target), amount])


func recover_actions(target, amount: int) -> void:
	note(_tr("LOG_ACTIONS_GAINED") % [_name(target), amount])


func force_talk(target) -> void:
	note(_tr("LOG_FORCED_TO_TALK") % _name(target))


func grant_examine_bonus(target, amount: int) -> void:
	note(_tr("LOG_EXAMINE_BONUS") % [amount, _name(target)])


func change_turn_order(_payload: Dictionary = {}) -> void:
	if timeline and rng:
		timeline.request_shuffle(rng)
	note(_tr("LOG_TURN_ORDER_SHUFFLED"))


## Sends the target to the back of next turn's order.
func move_to_last(target) -> void:
	if timeline:
		timeline.request_move_last(target)
	note(_tr("LOG_MOVED_LAST") % _name(target))


## Brings the target to the front of next turn's order.
func move_to_first(target) -> void:
	if timeline:
		timeline.request_move_first(target)
	note(_tr("LOG_MOVED_FIRST") % _name(target))


## Plumbing towards the UI, and deliberately silent: the effect calling it has already
## logged whatever the player should read. Logging the internal tag and its dictionary
## only cluttered the encounter log.
func request_ui(kind: StringName, data: Dictionary = {}) -> void:
	ui_requested.emit(kind, data)


# --- Targeting ---


## The user's own side, still standing, itself included.
func team() -> Array:
	return all_individuals.filter(
		func(f): return f.is_player == _user_is_player() and not f.is_dissolved()
	)


## The user's side, itself excluded.
func allies() -> Array:
	return team().filter(func(f): return f != user)


## Opponents still standing.
func opponents() -> Array:
	return all_individuals.filter(
		func(f): return f.is_player != _user_is_player() and not f.is_dissolved()
	)


## Everyone else still standing, on either side.
func others() -> Array:
	return all_individuals.filter(func(f): return f != user and not f.is_dissolved())


func random_of(arr: Array):
	return (
		arr[rng.randi_range(0, arr.size() - 1)]
		if rng and not arr.is_empty()
		else (arr[0] if not arr.is_empty() else null)
	)


func random_opponent():
	return random_of(opponents())


## The target the manager designated, or a random opponent if it named none.
func primary():
	return targets[0] if not targets.is_empty() else random_opponent()


## n opponents drawn at random, optionally without repeats.
func random_opponents(n: int, allow_repeat := true) -> Array:
	var pool := opponents()
	var out: Array = []
	for _i in n:
		if pool.is_empty():
			break
		var pick = random_of(pool)
		out.append(pick)
		if not allow_repeat:
			pool.erase(pick)
	return out


## The opponent standing first, or last, in the turn order.
func first_opponent_in_order():
	for f in _living_order():
		if f.is_player != _user_is_player():
			return f
	return null


func last_opponent_in_order():
	var found = null
	for f in _living_order():
		if f.is_player != _user_is_player():
			found = f
	return found


func _living_order() -> Array:
	return timeline.living() if timeline else all_individuals


func _user_is_player() -> bool:
	return user is EncounterIndividual and user.is_player


# --- Damage tiers ---


## Named damage tiers. The figures live in `data/balance.tres`.
func dmg(tier: StringName) -> int:
	return BalanceData.current().damage(tier)


## The ability's own damage if the doc gives a number, otherwise the "normal" tier.
func base_damage() -> int:
	return ability.base_damage if ability and ability.base_damage > 0 else dmg(&"normal")


# --- Weakness ---


func set_weakness(target, energy: GameEnums.Energy) -> void:
	if target is EncounterIndividual:
		target.override_weakness(energy)
	note(_tr("LOG_WEAKNESS_SET") % [_name(target), _energy_name(energy)])


func remove_weakness(target) -> void:
	set_weakness(target, GameEnums.Energy.NONE)


func reset_weakness(target) -> void:
	if target is EncounterIndividual:
		target.reset_weakness()
	note(_tr("LOG_WEAKNESS_RESET") % _name(target))


## Trades two individuals' exposed weaknesses (Dark Gambit, Dark Caroussel).
func swap_weakness(a, b) -> void:
	if a is EncounterIndividual and b is EncounterIndividual:
		var wa := weakness_of(a)
		var wb := weakness_of(b)
		a.override_weakness(wb)
		b.override_weakness(wa)
	note(_tr("LOG_WEAKNESS_SWAPPED") % [_name(a), _name(b)])


func lock_weakness(target) -> void:
	if target is EncounterIndividual:
		target.weakness_locked = true


func hide_weakness(target) -> void:
	if target is EncounterIndividual:
		target.weakness_hidden = true
	note(_tr("LOG_WEAKNESS_HIDDEN") % _name(target))


# --- Immunities and locks ---


func grant_immunity(target, energies: Array) -> void:
	if target is EncounterIndividual:
		target.immune_energies.append_array(energies)
	var names: Array = []
	for e in energies:
		names.append(_energy_name(e))
	note(_tr("LOG_IMMUNITY") % [_name(target), ", ".join(names)])


## Immune to everything EXCEPT this energy.
func grant_immunity_except(target, energy: GameEnums.Energy) -> void:
	if target is EncounterIndividual:
		target.immune_all_except = energy
	note(_tr("LOG_IMMUNITY_EXCEPT") % [_name(target), _energy_name(energy)])


## Multiplies what one energy does to the target this turn.
func set_energy_damage_factor(target, energy: GameEnums.Energy, factor: float) -> void:
	if target is EncounterIndividual:
		target.energy_damage_factor[energy] = target.energy_damage_factor.get(energy, 1.0) * factor
	note(_tr("LOG_ENERGY_DAMAGE_FACTOR") % [_energy_name(energy), _name(target), factor])


## The last of the user's own side in the turn order.
func last_of_team_in_order():
	var found = null
	for f in _living_order():
		if f.is_player == _user_is_player():
			found = f
	return found


func lock_den(target) -> void:
	if target is EncounterIndividual:
		target.den_locked = true


func lock_eth(target) -> void:
	if target is EncounterIndividual:
		target.eth_locked = true


func grant_reflect(target) -> void:
	if target is EncounterIndividual:
		target.reflect_to_attacker = true
	note(_tr("LOG_REFLECT") % _name(target))


func grant_full_immunity(target) -> void:
	if target is EncounterIndividual:
		target.fully_immune = true
	note(_tr("LOG_IMMUNITY_FULL") % _name(target))


## Narrows what the target may do. The action system does not exist; this logs.
##
## `allowed` carries TRANSLATION KEYS, never text: the UI_ENCOUNTER_ACTION_* the menu
## already uses, and the LOG_RESTRICT_* fragments for whatever the design doc phrases in
## prose. [method abilities_of_key] builds the energy-dependent ones.
func restrict_to(target, allowed: Array) -> void:
	var labels: Array = []
	for key in allowed:
		labels.append(String(TranslationServer.translate(key)))
	note(_tr("LOG_RESTRICTED") % [_name(target), ", ".join(labels)])


## The [method restrict_to] fragment for "abilities of this energy". Separate from
## [method _energy_name] because the two registers differ: a fragment is a label ("Heat
## abilities"), an energy name flows inside a sentence ("weakness of ravbak: heat").
func abilities_of_key(energy: GameEnums.Energy) -> String:
	return _ABILITIES_OF_KEYS.get(energy, "LOG_RESTRICT_ABILITIES_HEAT")


## Makes an individual flee. Fleeing does not exist; this logs.
func flee(target) -> void:
	note(_tr("LOG_FLEES") % _name(target))
	request_ui(
		&"flee", {"individual": target.species_id() if target is EncounterIndividual else target}
	)


# --- Counting and asking ---


## How many standing individuals come from a given Spiricosm.
func count_natives(spiricosm: GameEnums.Spiricosm) -> int:
	return (
		all_individuals
		. filter(
			func(f): return not f.is_dissolved() and f.species and f.species.spiricosm == spiricosm
		)
		. size()
	)


## The size of the largest group exposing the same weakness.
func largest_same_weakness_group() -> int:
	var counts := {}
	var best := 0
	for f in all_individuals:
		if f.is_dissolved():
			continue
		var w = f.active_weakness(
			timeline.position_of(f) if timeline else GameEnums.TurnPosition.MIDDLE
		)
		if w == GameEnums.Energy.NONE:
			continue
		counts[w] = counts.get(w, 0) + 1
		best = maxi(best, counts[w])
	return best


func weakness_of(individual) -> GameEnums.Energy:
	if individual is EncounterIndividual:
		return individual.active_weakness(
			timeline.position_of(individual) if timeline else GameEnums.TurnPosition.MIDDLE
		)
	return GameEnums.Energy.NONE


## Forces the ability's effective energy — for the ones that take on the user's own
## weakness. Changes both the damage conditions and which immunities apply.
func set_energy(energy: GameEnums.Energy) -> void:
	energy_override = energy


## The energy actually in play, override and Random/Variable resolved.
func energy() -> GameEnums.Energy:
	return _effective_energy()


# --- Helpers ---


func _random_energy_other_than(current: GameEnums.Energy) -> GameEnums.Energy:
	var pool := [
		GameEnums.Energy.HEAT,
		GameEnums.Energy.FLUID,
		GameEnums.Energy.CRYSTAL,
		GameEnums.Energy.ARCANE,
		GameEnums.Energy.TOXIC
	]
	pool.erase(current)
	return pool[rng.randi_range(0, pool.size() - 1)] if rng else pool[0]


func _name(target) -> String:
	if target is EncounterIndividual:
		return target.display_name()
	return str(target)


## The energy names the log spells out; the enum would otherwise print as a bare integer.
const _ENERGY_KEYS := {
	GameEnums.Energy.HEAT: "TERM_ENERGY_HEAT",
	GameEnums.Energy.FLUID: "TERM_ENERGY_FLUID",
	GameEnums.Energy.CRYSTAL: "TERM_ENERGY_CRYSTAL",
	GameEnums.Energy.ARCANE: "TERM_ENERGY_ARCANE",
	GameEnums.Energy.TOXIC: "TERM_ENERGY_TOXIC",
	GameEnums.Energy.RANDOM: "TERM_ENERGY_RANDOM",
	GameEnums.Energy.VARIABLE: "TERM_ENERGY_VARIABLE",
	GameEnums.Energy.NONE: "TERM_ENERGY_NONE",
}

## The [method restrict_to] fragment naming this energy's abilities, per energy. Only the
## five real energies have one: Random and Variable resolve before an ability restricts
## anything, and NONE restricts nothing.
const _ABILITIES_OF_KEYS := {
	GameEnums.Energy.HEAT: "LOG_RESTRICT_ABILITIES_HEAT",
	GameEnums.Energy.FLUID: "LOG_RESTRICT_ABILITIES_FLUID",
	GameEnums.Energy.CRYSTAL: "LOG_RESTRICT_ABILITIES_CRYSTAL",
	GameEnums.Energy.ARCANE: "LOG_RESTRICT_ABILITIES_ARCANE",
	GameEnums.Energy.TOXIC: "LOG_RESTRICT_ABILITIES_TOXIC",
}


func _energy_name(e: GameEnums.Energy) -> String:
	return String(TranslationServer.translate(_ENERGY_KEYS.get(e, "TERM_ENERGY_NONE")))


## Every line this class logs goes through here, so that none of them is ever written out
## in one language. See the LOG_* block in `translations/en.po`.
func _tr(key: String) -> String:
	return String(TranslationServer.translate(key))
