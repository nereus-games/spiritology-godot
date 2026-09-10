## One fighter in an encounter, player or rival: its state and the rules that govern it.
##
## A RefCounted logic object — combat state is kept apart from anything visual, which is
## what lets the whole encounter run headless.
##
## Which weakness is EXPOSED follows the fighter's position in the turn order, and an
## ability can override it for the current turn. Base DEN and ETH come from
## `data/balance.tres`; the doc gives no per-species stats yet.
class_name EncounterFighter
extends RefCounted

var species: SpeciesData
var is_player: bool
var max_den: int
var max_eth: int
var den: int
var eth: int

## Abilities this fighter can draw on. Players add what they have unlocked; rivals mostly
## have their native ones.
var ability_ids: Array[StringName] = []

## Multiplier on the NEXT damage taken — mitigation, amplification, or 0 for immunity.
## Spent on the next hit.
var next_damage_factor := 1.0
## When set, the next damage taken goes to this fighter instead (Victimism).
var redirect_to: EncounterFighter = null

# --- Per-turn state, wiped at the start of each round by clear_turn_state ---
var immune_energies: Array = []  ## énergies auxquelles immunisé ce tour
## Immune to EVERYTHING except this energy. NONE means the rule is off.
var immune_all_except := GameEnums.Energy.NONE
var fully_immune := false  ## immunisé à TOUS les dégâts ce tour
var den_locked := false  ## ne peut perdre de DEN
var eth_locked := false  ## ne peut perdre d'ETH
## Per-energy damage multipliers for this turn (Warning, Glaciation).
var energy_damage_factor: Dictionary = {}
## Sends the attacker as much damage as was taken (Reflux).
var reflect_to_attacker := false
var weakness_locked := false  ## faiblesse non modifiable (Isotropy)
var weakness_hidden := false  ## faiblesse cachée aux rivaux (UI)
## Whoever last cost this fighter DEN or ETH (Cold Wave, Growth Mindset).
var last_damager: EncounterFighter = null
## Bonus on damage this fighter DEALS this turn (Meditate). Added alongside the
## per-condition modifiers in [method EncounterContext._apply_modifiers].
var outgoing_damage_bonus := 0.0
## Scheduled for NEXT turn; promoted by [method clear_turn_state].
var _pending_outgoing_bonus := 0.0

var _used_single: Dictionary = {}  ## id -> true (usage unique consommé)
var _weakness_override := false
var _weakness_energy := GameEnums.Energy.NONE  ## faiblesse forcée pour le tour courant


func _init(p_species: SpeciesData, p_is_player: bool) -> void:
	species = p_species
	is_player = p_is_player
	var balance := BalanceData.current()
	max_den = balance.base_den
	max_eth = balance.base_eth
	den = max_den
	eth = max_eth
	if species:
		_populate_abilities()


## Native abilities, plus the also-used ones, plus whatever the encyclopaedia unlocked.
## Filtering to ENCOUNTER type happens later, when the manager offers a choice.
func _populate_abilities() -> void:
	var seen := {}
	for list in [
		species.origin_abilities, species.also_used_abilities, species.encyclopaedia_abilities
	]:
		for aid in list:
			if not seen.has(aid):
				seen[aid] = true
				ability_ids.append(aid)


func species_id() -> StringName:
	return species.id if species else &""


func display_name() -> String:
	return String(TranslationServer.translate(species.name_key())) if species else "?"


func is_dissolved() -> bool:
	return den <= 0


## The weakness currently exposed: the one for this position, unless overridden.
func active_weakness(position: GameEnums.TurnPosition) -> GameEnums.Energy:
	if _weakness_override:
		return _weakness_energy
	return species.weakness_for(position) if species else GameEnums.Energy.NONE


## Forces the exposed weakness for this turn. Refused while the weakness is locked
## (Isotropy). NONE means "no weakness at all".
func override_weakness(energy: GameEnums.Energy) -> void:
	if weakness_locked:
		return
	_weakness_override = true
	_weakness_energy = energy


## Drops the override, back to the weakness the position implies.
func reset_weakness() -> void:
	if not weakness_locked:
		_weakness_override = false


## Immune to this energy for the turn.
func is_immune_to(energy: GameEnums.Energy) -> bool:
	if fully_immune:
		return true
	if energy in immune_energies:
		return true
	if immune_all_except != GameEnums.Energy.NONE and energy != immune_all_except:
		return true
	return false


## Schedules a damage bonus for the NEXT turn (Meditate: "damage +Y % until next turn").
##
## Two-step on purpose. [method clear_turn_state] wipes per-turn state at the start of each
## round, so a bonus applied directly would be erased before the meditating fighter got to
## act — Meditate would never do anything at all.
func grant_next_turn_damage_bonus(bonus: float) -> void:
	_pending_outgoing_bonus = bonus


## Wipes per-turn state: overrides, immunities, locks. Called at the start of a round.
func clear_turn_state() -> void:
	# Promote the scheduled bonus BEFORE wiping — see grant_next_turn_damage_bonus.
	outgoing_damage_bonus = _pending_outgoing_bonus
	_pending_outgoing_bonus = 0.0
	_weakness_override = false
	immune_energies = []
	immune_all_except = GameEnums.Energy.NONE
	fully_immune = false
	den_locked = false
	eth_locked = false
	weakness_locked = false
	weakness_hidden = false
	energy_damage_factor = {}
	reflect_to_attacker = false


func apply_damage(amount: int) -> void:
	if den_locked:
		return
	den = maxi(den - amount, 0)


## ETH lost to someone else's ability. Blocked by [member eth_locked].
func drain_eth(amount: int) -> void:
	if eth_locked:
		return
	eth = maxi(eth - amount, 0)


## Paying for one's own ability, which is voluntary — so it deliberately ignores
## [member eth_locked]. That lock exists to protect against enemy drain, not to make
## abilities free.
func pay_eth(amount: int) -> void:
	eth = maxi(eth - amount, 0)


func recover_den(amount: int) -> void:
	den = mini(den + amount, max_den)


func recover_eth(amount: int) -> void:
	eth = mini(eth + amount, max_eth)


## Seeds current DEN/ETH from persistent state.
##
## The integration point with [GameSession]: called for PLAYER fighters so that damage
## taken in earlier encounters is not forgotten between them.
func load_persistent_state(p_den: int, p_eth: int) -> void:
	den = clampi(p_den, 0, max_den)
	eth = clampi(p_eth, 0, max_eth)


## Whether a single-use ability has already been spent this encounter.
func is_spent(ability: AbilityData) -> bool:
	return ability.single_use and _used_single.has(ability.id)


func can_afford(ability: AbilityData) -> bool:
	return eth >= ability.eth_cost()


## Playable right now: neither spent nor unaffordable.
func can_use(ability: AbilityData) -> bool:
	return not is_spent(ability) and can_afford(ability)


func mark_used(ability: AbilityData) -> void:
	if ability.single_use:
		_used_single[ability.id] = true


## Un-spends a single-use ability, making it available again this encounter. Used by the
## Reuse talent (jézal).
func clear_used(ability: AbilityData) -> void:
	_used_single.erase(ability.id)


## Breaks the references to OTHER fighters ([member last_damager], [member redirect_to]).
## Call it once the encounter is over.
##
## Necessary, not merely tidy: two fighters that have hit each other point at each other,
## which is a RefCounted CYCLE, and Godot does not collect cycles. The fighters of a
## finished encounter would stay in memory — along with their [SpeciesData] — until the
## game closed. Both fields are transient combat state that is never displayed, so
## clearing them afterwards costs nothing.
func release_cross_references() -> void:
	last_damager = null
	redirect_to = null
