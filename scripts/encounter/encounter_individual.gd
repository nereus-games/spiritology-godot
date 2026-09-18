## One individual in an encounter, player or rival: its state and the rules that govern it.
##
## A RefCounted logic object — combat state is kept apart from anything visual, which is
## what lets the whole encounter run headless.
##
## Which weakness is EXPOSED follows the individual's position in the turn order, and an
## ability can override it for a while. Base DEN and ETH come from `data/balance.tres`; the doc
## gives no per-species stats yet.
##
## [b]How long an effect lasts.[/b] The doc words nearly every timed effect as "until its next
## turn" — and in French *tour* is both the round and a turn, so "until the end of the turn"
## reads the same way. An effect is therefore ANCHORED to an individual, normally whoever
## caused it, and lasts a number of that individual's turns: [constant UNTIL_NEXT_TURN] ends
## it as the anchor's next turn begins, 2 carries it through one more, and
## [constant FOR_ENCOUNTER] never ends it — though another effect may overwrite it.
##
## Wiping everything at the start of each round, which is what this replaced, cut every effect
## short by however far down the order its author stood: Effort of Neutrality used by the
## second individual of the order gave back both weaknesses before either could matter.
class_name EncounterIndividual
extends RefCounted

var species: SpeciesData
var is_player: bool
var max_den: int
var max_eth: int
var den: int
var eth: int

## Abilities this individual can draw on. Players add what they have unlocked; rivals mostly
## have their native ones.
var ability_ids: Array[StringName] = []

## Multiplier on the NEXT damage taken — mitigation, amplification, or 0 for immunity.
## Spent on the next hit.
var next_damage_factor := 1.0
## When set, the next damage taken goes to this individual instead (Victimism).
var redirect_to: EncounterIndividual = null

## A timed effect lasts until its anchor's next turn begins. See the class description.
const UNTIL_NEXT_TURN := 1
## A timed effect that never runs out on its own.
const FOR_ENCOUNTER := 0

# --- Timed state: each field set through a method below, which arms its timer ---
var immune_energies: Array = []  ## The energies it is immune to this turn
## Immune to EVERYTHING except this energy. NONE means the rule is off.
var immune_all_except := GameEnums.Energy.NONE
var fully_immune := false  ## Immune to ALL damage this turn
var den_locked := false  ## Cannot lose DEN
var den_frozen := false  ## Can neither lose nor gain DEN (Isotropy)
var eth_locked := false  ## Cannot lose ETH
## Per-energy damage multipliers for this turn (Warning, Glaciation).
var energy_damage_factor: Dictionary = {}
## Sends the attacker as much damage as was taken (Reflux).
var reflect_to_attacker := false
var weakness_locked := false  ## Weakness cannot be changed (Isotropy)
var weakness_hidden := false  ## Weakness concealed from the rivals (UI only)
## Whoever last cost this individual DEN or ETH (Cold Wave, Growth Mindset).
var last_damager: EncounterIndividual = null
## Bonus on damage this individual DEALS (Meditate). Added alongside the per-condition
## modifiers in [method EncounterContext._apply_modifiers].
var outgoing_damage_bonus := 0.0

## Why this individual left the encounter before its end — [constant EncounterManager.FLED]
## or [constant EncounterManager.PACIFIED] — or &"" while it is still in it. Set by
## [method EncounterManager.withdraw], and only there.
##
## Leaving is not being dissolved: the individual comes out with whatever DEN it has left,
## and in exploration it carries on with it.
var departure := &""

var _used_single: Dictionary = {}  ## ability id -> true, once its single use is spent
var _weakness_override := false
var _weakness_energy := GameEnums.Energy.NONE  ## The weakness forced for now
## Timers of the timed state: key (see [method _expire]) -> [anchor instance id, turns left].
## An instance id rather than the anchor itself, so that no reference cycle can form.
var _timers: Dictionary = {}


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


## Whether it left the encounter before the end, fleeing or pacified.
func has_left() -> bool:
	return departure != &""


## The weakness currently exposed: the one for this position, unless overridden.
func active_weakness(position: GameEnums.TurnPosition) -> GameEnums.Energy:
	if _weakness_override:
		return _weakness_energy
	return species.weakness_for(position) if species else GameEnums.Energy.NONE


## Forces the exposed weakness, anchored to `anchor` (itself when null) for `turns` of the
## anchor's turns. Refused while the weakness is locked (Isotropy). NONE means "no weakness at
## all". True if it took.
func override_weakness(
	energy: GameEnums.Energy, anchor: EncounterIndividual = null, turns := UNTIL_NEXT_TURN
) -> bool:
	if weakness_locked:
		return false
	_weakness_override = true
	_weakness_energy = energy
	_arm("weakness", anchor, turns)
	return true


## Drops the override, back to the weakness the position implies.
func reset_weakness() -> void:
	if not weakness_locked:
		_expire("weakness")


func lock_weakness(anchor: EncounterIndividual = null, turns := UNTIL_NEXT_TURN) -> void:
	weakness_locked = true
	_arm("weakness_locked", anchor, turns)


func hide_weakness(anchor: EncounterIndividual = null, turns := UNTIL_NEXT_TURN) -> void:
	weakness_hidden = true
	_arm("weakness_hidden", anchor, turns)


func add_immunity(
	energy: GameEnums.Energy, anchor: EncounterIndividual = null, turns := UNTIL_NEXT_TURN
) -> void:
	if not immune_energies.has(energy):
		immune_energies.append(energy)
	_arm("immune:%d" % energy, anchor, turns)


func set_immune_all_except(
	energy: GameEnums.Energy, anchor: EncounterIndividual = null, turns := UNTIL_NEXT_TURN
) -> void:
	immune_all_except = energy
	_arm("immune_all_except", anchor, turns)


func set_fully_immune(anchor: EncounterIndividual = null, turns := UNTIL_NEXT_TURN) -> void:
	fully_immune = true
	_arm("fully_immune", anchor, turns)


func lock_den(anchor: EncounterIndividual = null, turns := UNTIL_NEXT_TURN) -> void:
	den_locked = true
	_arm("den_locked", anchor, turns)


## DEN can go neither down nor up (Isotropy).
func freeze_den(anchor: EncounterIndividual = null, turns := UNTIL_NEXT_TURN) -> void:
	den_frozen = true
	_arm("den_frozen", anchor, turns)


func lock_eth(anchor: EncounterIndividual = null, turns := UNTIL_NEXT_TURN) -> void:
	eth_locked = true
	_arm("eth_locked", anchor, turns)


## Multiplies what one energy does to it. Factors from several effects multiply together.
func scale_energy_damage(
	energy: GameEnums.Energy,
	factor: float,
	anchor: EncounterIndividual = null,
	turns := UNTIL_NEXT_TURN
) -> void:
	energy_damage_factor[energy] = energy_damage_factor.get(energy, 1.0) * factor
	_arm("factor:%d" % energy, anchor, turns)


func set_reflect(anchor: EncounterIndividual = null, turns := UNTIL_NEXT_TURN) -> void:
	reflect_to_attacker = true
	_arm("reflect", anchor, turns)


## Immune to this energy for the turn.
func is_immune_to(energy: GameEnums.Energy) -> bool:
	if fully_immune:
		return true
	if energy in immune_energies:
		return true
	if immune_all_except != GameEnums.Energy.NONE and energy != immune_all_except:
		return true
	return false


## A damage bonus for its NEXT turn (Meditate: "damage +Y % until next turn").
##
## Two turns of its own, because Meditate spends the current one: the bonus has to be there
## when it next acts, and gone the turn after.
func grant_next_turn_damage_bonus(bonus: float) -> void:
	outgoing_damage_bonus = bonus
	_arm("outgoing_bonus", self, 2)


## A turn begins — `individual`'s. Everything anchored to it counts down one turn, and what
## runs out expires. The manager calls this on EVERY individual at the start of each turn,
## including the turns a dissolved individual skips, so that its effects still run out.
func on_turn_start(individual: EncounterIndividual) -> void:
	var id := individual.get_instance_id()
	for key in _timers.keys():
		var timer: Array = _timers[key]
		if timer[0] != id:
			continue
		timer[1] -= 1
		if timer[1] <= 0:
			_expire(key)


## Ends at once every effect anchored to `individual` — which left the encounter, and so will
## never have the next turn they were waiting for.
func expire_anchored_to(individual: EncounterIndividual) -> void:
	var id := individual.get_instance_id()
	for key in _timers.keys():
		if _timers[key][0] == id:
			_expire(key)


func _arm(key: String, anchor: EncounterIndividual, turns: int) -> void:
	if turns == FOR_ENCOUNTER:
		_timers.erase(key)
		return
	var who := anchor if anchor != null else self
	_timers[key] = [who.get_instance_id(), turns]


## Puts one timed field back to rest. Direct assignment on purpose: a timer that runs out
## ends the weakness override even while a lock is on, since the two run out together.
func _expire(key: String) -> void:
	_timers.erase(key)
	if key.begins_with("immune:"):
		immune_energies.erase(int(key.get_slice(":", 1)))
		return
	if key.begins_with("factor:"):
		energy_damage_factor.erase(int(key.get_slice(":", 1)))
		return
	match key:
		"weakness":
			_weakness_override = false
		"weakness_locked":
			weakness_locked = false
		"weakness_hidden":
			weakness_hidden = false
		"immune_all_except":
			immune_all_except = GameEnums.Energy.NONE
		"fully_immune":
			fully_immune = false
		"den_locked":
			den_locked = false
		"den_frozen":
			den_frozen = false
		"eth_locked":
			eth_locked = false
		"reflect":
			reflect_to_attacker = false
		"outgoing_bonus":
			outgoing_damage_bonus = 0.0


func apply_damage(amount: int) -> void:
	if den_locked or den_frozen:
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
	if den_frozen:
		return
	den = mini(den + amount, max_den)


func recover_eth(amount: int) -> void:
	eth = mini(eth + amount, max_eth)


## Seeds current DEN/ETH from persistent state.
##
## The integration point with [GameSession]: called for PLAYER individuals so that damage
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


## Breaks the references to OTHER individuals ([member last_damager], [member redirect_to]).
## Call it once the encounter is over.
##
## Necessary, not merely tidy: two individuals that have hit each other point at each other,
## which is a RefCounted CYCLE, and Godot does not collect cycles. The individuals of a
## finished encounter would stay in memory — along with their [SpeciesData] — until the
## game closed. Both fields are transient combat state that is never displayed, so
## clearing them afterwards costs nothing.
func release_cross_references() -> void:
	last_damager = null
	redirect_to = null
