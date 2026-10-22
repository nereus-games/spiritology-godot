## The state of a playthrough (autoload `GameSession`).
##
## Everything that changes as the game is played and therefore has to be saved: the duo,
## encyclopaedia progress, dungeon states, PSY score, inventory. The counterpart of
## [GameData], which is static and reloaded at boot. Serialised by [SaveSystem].
extends Node

const EncyclopaediaModel := preload("res://scripts/encyclopaedia/encyclopaedia_model.gd")

## PSY thresholds that decide how much IFP an action earns.
const PSY_LOW := 10
const PSY_HIGH := 30

## Perfect encounters in a row before the FDE counter converts into +1 PSY.
const FDE_THRESHOLD := 3

## Ceiling on the IFP a single species can yield through "Examine decor / ground".
## Distinct from a page's own 0..100: this one SOURCE can never give more than this.
const EXAMINE_DECOR_CAP := 15

## IFP per (action, PSY tier). Source: design doc, Encyclopaedia / "Obtaining
## Info Points". Each entry is `[tier 0, tier 1, tier 2]`, indexed by [method psy_tier].
##
## Forlorn variants are separate rows; falling back from Forlorn to ordinary when the main
## page is incomplete happens in [method ifp_amount], not here.
const IFP_TABLE := {
	# Examining decor has no Forlorn variant.
	GameEnums.IfpAction.EXAMINE_DECOR:
	{
		false: [3, 3, 2],
	},
	GameEnums.IfpAction.EXAMINE_RIVAL:
	{
		false: [6, 8, 9],
		true: [12, 13, 14],  # Forlorn, and only once the main page is complete
	},
	GameEnums.IfpAction.TALK_RIVAL:
	{
		false: [2, 2, 1],
		true: [4, 4, 2],
	},
	GameEnums.IfpAction.DISSOLVE_RIVAL:
	{
		false: [1, 2, 2],
		true: [2, 3, 4],
	},
	# Examine Weakness: "a little info" is one fragment, i.e. EncyclopaediaModel.IFP_PER_FRAGMENT
	# IFP at every PSY tier. The Forlorn row is the ordinary one.
	GameEnums.IfpAction.WEAKNESS_INFO:
	{
		false: [3, 3, 3],
	},
}

## A player character's maximum DEN (Density), fixed for the whole game.
const MAX_DEN := 100

## Rough magnitudes for an ordinary rival's DEN as the game progresses (design doc, Game
## Units / Density).
##
## NOT tiers applied automatically. A rival's starting DEN is assigned by LEVEL DESIGN,
## dungeon by dungeon, aiming at these magnitudes — hence reference constants rather than
## game state.
const RIVAL_DEN_EARLY := 50
const RIVAL_DEN_MID := 100
const RIVAL_DEN_LATE := 125

## A player character's maximum ETH (Ether).
## ## TODO: per-species maximum once the doc gives figures. Kept in step with
## [member BalanceData.base_eth].
const MAX_ETH := 50

## The two slots of the playable duo. Indexes [member party_den] / [member party_eth].
enum PartySlot { MAIN, TEAMMATE }

signal psy_changed(new_value: int)
signal fde_changed(new_value: int)
## The MAIN page of a species gained or lost IFP. The Forlorn page has its own signal below.
signal encyclopaedia_progress(species_id: StringName, ifp: int)
## Any page of a species changed (IFP, fragments, a revealed ability), the Forlorn one included.
signal encyclopaedia_page_changed(species_id: StringName, forlorn: bool)
## IFP crossed a multiple of 3: `count` new true fragments, and as many parasitic ones, have
## formed. "New encyclopaedia fragments have formed."
signal encyclopaedia_fragments_formed(species_id: StringName, forlorn: bool, count: int)
## Correctly arranging fragments revealed an ability, which is usable from now on.
signal encyclopaedia_ability_unlocked(species_id: StringName, ability_id: StringName)
## A page reached 100 % through a correct full assembly.
signal encyclopaedia_page_assembled(species_id: StringName, forlorn: bool)
## A slot's persistent DEN changed — damage, healing, or recovery from devitalisation.
signal den_changed(slot: PartySlot, new_value: int)
## A slot's persistent ETH changed.
signal eth_changed(slot: PartySlot, new_value: int)
## BOTH characters are devitalised at once, and each has been restored to 1 DEN.
## Exploration is expected to answer this by taking the duo out of the dungeon.
signal party_wiped
## An inventory quantity changed. `new_count` is 0 when the last one is spent.
signal inventory_changed(object_id: StringName, new_count: int)

## The playable duo, decided by the personality quiz. The same species can fill both
## slots, in which case its talent stacks.
##
## Setting either grants the duo's starting fragments ([method
## EncyclopaediaModel.grant_starting_duo]), whoever sets it: the quiz, a loaded save, a dev
## scenario.
var main_character: StringName:
	set(value):
		main_character = value
		_grant_starting_duo()
var teammate: StringName:
	set(value):
		teammate = value
		_grant_starting_duo()

## What the player named the main character.
var player_name: String = ""

## Persistent DEN per slot. It lasts the whole game: damage taken in an encounter is NOT
## forgotten when the encounter ends.
var party_den: Dictionary = {
	PartySlot.MAIN: MAX_DEN,
	PartySlot.TEAMMATE: MAX_DEN,
}

## Persistent ETH per slot. Fully restored on entering a dungeon
## ([method restore_party_eth]).
var party_eth: Dictionary = {
	PartySlot.MAIN: MAX_ETH,
	PartySlot.TEAMMATE: MAX_ETH,
}

## The psychological score. Decides which row of [constant IFP_TABLE] applies.
var psy_score: int = 0:
	set(value):
		psy_score = value
		psy_changed.emit(psy_score)

## Full Devitalisation Encounters — a "murderous spree" counter, hidden from the player.
## Counts encounters where EVERY rival was devitalised, and resets the moment one ends any
## other way. At [constant FDE_THRESHOLD] it converts into +1 PSY.
var fde_count: int = 0:
	set(value):
		fde_count = value
		fde_changed.emit(fde_count)

## The encyclopaedia: a main page and a Forlorn page per species, their IFP, fragments and the
## abilities arranging them revealed. Read it through the methods below; see
## [EncyclopaediaModel] for the rules.
var encyclopaedia := EncyclopaediaModel.new()

## How much each species has already yielded through "Examine decor / ground", so that
## [constant EXAMINE_DECOR_CAP] can be enforced across a whole playthrough.
var exploration_examine_ifp: Dictionary = {}

## Per-dungeon persistent state: dungeon_id -> Dictionary of visited tiles and the like.
var dungeon_states: Dictionary = {}

## Exploration abilities already spent this dungeon visit. Each is usable ONCE per visit;
## the litter's Recycle action refreshes one at random, a refresh crystal refreshes all.
## Cleared on entering a dungeon.
var used_exploration_abilities: Dictionary = {}

## Has no encounter begun yet in this dungeon visit? Set on entering a dungeon and spent by the
## first encounter ([method take_first_encounter]). Like [member used_exploration_abilities],
## it is per visit and so is not worth saving. At a high PSY the teammate refuses the first
## action of that encounter.
var first_encounter_pending := true

## Inventory: object slug -> quantity. Objects stack, so they are counted rather than
## duplicated, and an entry reaching 0 is erased. No object is needed to finish the game.
var inventory: Dictionary = {}


## Which row of [constant IFP_TABLE] the current PSY score selects.
func psy_tier() -> int:
	if psy_score <= PSY_LOW:
		return 0
	if psy_score <= PSY_HIGH:
		return 1
	return 2


## Is the PSY score strictly above rung `rung` (1 to 4) of the doc's ladder? The rungs are
## [member BalanceData.psy_rung_1] to `_4` (10, 20, 30, 40). Every PSY consequence asks this
## rather than comparing the score itself.
func psy_above(rung: int) -> bool:
	var balance := BalanceData.current()
	var thresholds := [
		balance.psy_rung_1, balance.psy_rung_2, balance.psy_rung_3, balance.psy_rung_4
	]
	return psy_score > thresholds[clampi(rung, 1, 4) - 1]


## Does the PSY ladder forbid Meditate and objects right now? Rung 4 (PSY above 40) with the
## player poisoned. `poisoned` is passed in because poison lives on the exploration actor, not
## here. The map, encyclopaedia and team views are forbidden too by the doc.
## TODO: gate those three once the views exist; they should ask this same function.
func psy_forbids_while_poisoned(poisoned: bool) -> bool:
	return poisoned and psy_above(4)


## Has this species been entered in the encyclopaedia at all?
##
## Gates what the encounter UI may show: "rival's density and weakness aren't shown in
## timeline if they aren't in the encyclopaedia (yet)".
func knows_species(species_id: StringName) -> bool:
	return encyclopaedia.knows(species_id)


## Adds IFP to a species' page (its Forlorn page if `forlorn_page`). A page stops at 99 %: the
## last one comes from [method mark_page_assembled]. Forms fragments, and returns the IFP
## actually added, which is 0 for a page at the cap.
func add_ifp(species_id: StringName, amount: int, forlorn_page: bool = false) -> int:
	var fragments_before := encyclopaedia.true_fragments(species_id, forlorn_page)
	var added := encyclopaedia.add_ifp(species_id, amount, forlorn_page)
	if added > 0:
		_page_changed(species_id, forlorn_page)
		var formed := encyclopaedia.true_fragments(species_id, forlorn_page) - fragments_before
		if formed > 0:
			encyclopaedia_fragments_formed.emit(species_id, forlorn_page, formed)
	return added


# --- Encyclopaedia pages and fragments ---


## A page's percentage: 0 to 99 from IFP, 100 once assembled.
func page_ifp(species_id: StringName, forlorn_page: bool = false) -> int:
	return encyclopaedia.ifp(species_id, forlorn_page)


## 100 %, i.e. correctly assembled. This is what the "page complete" damage condition and the
## Forlorn bonus IFP read.
func is_page_complete(species_id: StringName, forlorn_page: bool = false) -> bool:
	return encyclopaedia.is_complete(species_id, forlorn_page)


## Species whose main page is complete, for [member EncounterManager.completed_species].
func completed_species() -> Dictionary:
	return encyclopaedia.completed_species()


func true_fragments(species_id: StringName, forlorn_page: bool = false) -> int:
	return encyclopaedia.true_fragments(species_id, forlorn_page)


func parasitic_fragments(species_id: StringName, forlorn_page: bool = false) -> int:
	return encyclopaedia.parasitic_fragments(species_id, forlorn_page)


func arranged_fragments(species_id: StringName, forlorn_page: bool = false) -> int:
	return encyclopaedia.arranged_fragments(species_id, forlorn_page)


## The abilities the encyclopaedia has revealed for a species, in unlock order.
func unlocked_abilities(species_id: StringName) -> Array[StringName]:
	return encyclopaedia.unlocked_abilities(GameData.species(species_id))


## Every ability a player character of this species may use: the native ones, minus those the
## encyclopaedia gates and has not revealed, plus those it has. See
## [method EncyclopaediaModel.usable_abilities]. What a player-side catalogue must read.
func usable_abilities(species_id: StringName) -> Array[StringName]:
	return encyclopaedia.usable_abilities(GameData.species(species_id))


## The puzzle reports how many true fragments are correctly arranged on a page. Reveals any
## ability whose threshold (15, 30; 15 on a Forlorn page) is reached; one already revealed is
## never taken back.
func set_arranged_fragments(species_id: StringName, forlorn_page: bool, count: int) -> void:
	var before := unlocked_abilities(species_id)
	var arranged_before := encyclopaedia.arranged_fragments(species_id, forlorn_page)
	encyclopaedia.set_arranged(species_id, forlorn_page, count)
	_announce_unlocks(species_id, before)
	if encyclopaedia.arranged_fragments(species_id, forlorn_page) != arranged_before:
		encyclopaedia_page_changed.emit(species_id, forlorn_page)


## The puzzle destroyed true fragments: the page loses 3 IFP each. Returns how many. The puzzle
## then reports the new arranged count through [method set_arranged_fragments].
func destroy_fragments(species_id: StringName, forlorn_page: bool, count: int = 1) -> int:
	var destroyed := encyclopaedia.destroy_fragments(species_id, forlorn_page, count)
	if destroyed > 0:
		_page_changed(species_id, forlorn_page)
	return destroyed


## Parasitic fragments disappeared after a wrong assembly. Returns how many.
func remove_parasitic_fragments(species_id: StringName, forlorn_page: bool, count: int = 1) -> int:
	var removed := encyclopaedia.remove_parasitic(species_id, forlorn_page, count)
	if removed > 0:
		encyclopaedia_page_changed.emit(species_id, forlorn_page)
	return removed


## The puzzle calls this when a page has been assembled correctly and completely: 99 % becomes
## 100 %. Returns false, changing nothing, unless the page is at 99 % with all 33 true fragments
## reported arranged.
func mark_page_assembled(species_id: StringName, forlorn_page: bool = false) -> bool:
	var before := unlocked_abilities(species_id)
	if not encyclopaedia.mark_assembled(species_id, forlorn_page):
		return false
	_page_changed(species_id, forlorn_page)
	_announce_unlocks(species_id, before)
	encyclopaedia_page_assembled.emit(species_id, forlorn_page)
	return true


func _grant_starting_duo() -> void:
	for id in encyclopaedia.grant_starting_duo(main_character, teammate):
		_page_changed(id, false)


func _page_changed(species_id: StringName, forlorn_page: bool) -> void:
	if not forlorn_page:
		encyclopaedia_progress.emit(species_id, encyclopaedia.ifp(species_id))
	encyclopaedia_page_changed.emit(species_id, forlorn_page)


func _announce_unlocks(species_id: StringName, before: Array[StringName]) -> void:
	for aid in unlocked_abilities(species_id):
		if not (aid in before):
			encyclopaedia_ability_unlocked.emit(species_id, aid)


# --- Earning IFP ---


## The raw table amount for an action at the current PSY tier. Pure: changes no state.
##
## A Forlorn rival only yields its higher amounts once the species' ordinary page is
## complete; otherwise the ordinary row applies. `main_page_complete` carries that, worked
## out by the caller.
func ifp_amount(
	action: GameEnums.IfpAction, is_forlorn: bool, main_page_complete: bool = false
) -> int:
	var use_forlorn := is_forlorn and main_page_complete
	var variants: Dictionary = IFP_TABLE[action]
	# EXAMINE_DECOR has no Forlorn row to fall back from.
	var by_tier: Array = variants.get(use_forlorn, variants[false])
	return by_tier[psy_tier()]


## Scales a whole number of IFP by a factor, and says how it is rounded: AWAY from the original
## amount. A factor below 1 (Hardening's Talk penalty) rounds down, a factor above 1 (every
## "more info" bonus on an Examine) rounds up, so that neither ever vanishes on a small table
## amount: +10 % on 6 IFP is 7, not 6, and a penalty on 1 or 2 IFP bites. A product within a
## millionth of a whole number counts as that number, so that float noise (10 * 1.1 is
## 11.000000000000002) never costs a point. Pure.
func scale_amount(amount: int, factor: float) -> int:
	if is_equal_approx(factor, 1.0):
		return amount
	var scaled := amount * factor
	if factor > 1.0:
		return ceili(scaled - 0.000001)
	return floori(scaled + 0.000001)


## Awards the IFP for an action, and returns what was actually added.
##
## The single entry point, because it is where the doc's three restrictions live:
##   - an ineffective Talk earns nothing;
##   - Forlorn falls back to the ordinary row while the main page is incomplete;
##   - `yield_factor` scales the table's amount, rounded as [method scale_amount] says (see
##     [signal EncounterManager.ifp_earned]);
##   - examining decor is capped per species at [constant EXAMINE_DECOR_CAP], truncated on
##     the way to the cap and 0 once reached.
##   - a Forlorn rival's points (once the main page is complete) go to the species' FORLORN
##     page, with its own percentage; before that they are an ordinary rival's, on the main one;
##   - a page stops at 99 % ([method add_ifp]), and what it could not take is not counted
##     against the decor ceiling.
## Called directly by exploration (examinable decor, litter, crumbly ground); encounters go
## through [signal EncounterManager.ifp_earned], relayed here by the encounter UI.
func award_ifp(
	species_id: StringName,
	action: GameEnums.IfpAction,
	is_forlorn: bool = false,
	dialogue_effective: bool = true,
	yield_factor: float = 1.0
) -> int:
	# An ineffective Talk earns nothing.
	if action == GameEnums.IfpAction.TALK_RIVAL and not dialogue_effective:
		return 0
	var main_page_complete := encyclopaedia.is_complete(species_id)
	var forlorn_page := is_forlorn and main_page_complete
	var amount := ifp_amount(action, is_forlorn, main_page_complete)
	amount = scale_amount(amount, yield_factor)
	# A page at 99 % takes nothing more.
	amount = mini(amount, encyclopaedia.room(species_id, forlorn_page))
	# Per-species ceiling on what examining decor can ever yield.
	if action == GameEnums.IfpAction.EXAMINE_DECOR:
		var already: int = exploration_examine_ifp.get(species_id, 0)
		var room := EXAMINE_DECOR_CAP - already
		if room <= 0:
			return 0
		amount = mini(amount, room)
		if amount > 0:
			exploration_examine_ifp[species_id] = already + amount
	if amount <= 0:
		return 0
	return add_ifp(species_id, amount, forlorn_page)


# --- The duo's talents ---


## Does the duo carry this talent? A talent belongs to a SPECIES, so the duo has it if
## either member is of that species.
##
## Needed OUTSIDE encounters, where no [EncounterIndividual] exists to carry a [TalentScript] —
## which is exactly the case for the exploration talents: chests, traps, the map.
func party_has_talent(talent_id: StringName) -> bool:
	return party_talent_stacks(talent_id) > 0


## How many copies of the talent the duo carries — 0, 1, or 2 when both members share the
## species.
func party_talent_stacks(talent_id: StringName) -> int:
	var stacks := 0
	for member in [main_character, teammate]:
		if member == &"":
			continue
		var sp: SpeciesData = GameData.species(member)
		if sp != null and sp.talent == talent_id:
			stacks += 1
	return stacks


# --- The duo's persistent DEN / ETH ---


func get_den(slot: PartySlot) -> int:
	return party_den.get(slot, MAX_DEN)


func get_eth(slot: PartySlot) -> int:
	return party_eth.get(slot, MAX_ETH)


## Sets a slot's DEN, clamped, and signals only on an actual change.
func set_den(slot: PartySlot, value: int) -> void:
	var clamped := clampi(value, 0, MAX_DEN)
	if party_den.get(slot) == clamped:
		return
	party_den[slot] = clamped
	den_changed.emit(slot, clamped)


## Sets a slot's ETH, clamped, and signals only on an actual change.
func set_eth(slot: PartySlot, value: int) -> void:
	var clamped := clampi(value, 0, MAX_ETH)
	if party_eth.get(slot) == clamped:
		return
	party_eth[slot] = clamped
	eth_changed.emit(slot, clamped)


func apply_den_damage(slot: PartySlot, amount: int) -> int:
	set_den(slot, get_den(slot) - maxi(amount, 0))
	return get_den(slot)


func heal_den(slot: PartySlot, amount: int) -> int:
	set_den(slot, get_den(slot) + maxi(amount, 0))
	return get_den(slot)


func spend_eth(slot: PartySlot, amount: int) -> int:
	set_eth(slot, get_eth(slot) - maxi(amount, 0))
	return get_eth(slot)


func recover_eth(slot: PartySlot, amount: int) -> int:
	set_eth(slot, get_eth(slot) + maxi(amount, 0))
	return get_eth(slot)


## "Fully restored when entering a dungeon".
func restore_party_eth() -> void:
	set_eth(PartySlot.MAIN, MAX_ETH)
	set_eth(PartySlot.TEAMMATE, MAX_ETH)


## Devitalised: DEN has reached 0.
func is_devitalised(slot: PartySlot) -> bool:
	return get_den(slot) <= 0


func is_party_wiped() -> bool:
	return is_devitalised(PartySlot.MAIN) and is_devitalised(PartySlot.TEAMMATE)


## Applies the wipe rule: each member back to 1 DEN, then [signal party_wiped] so that
## exploration takes the duo out of the dungeon. Does nothing unless both are down.
func resolve_party_wipe() -> bool:
	if not is_party_wiped():
		return false
	set_den(PartySlot.MAIN, 1)
	set_den(PartySlot.TEAMMATE, 1)
	party_wiped.emit()
	return true


## Updates the FDE counter at the end of an encounter. `all_rivals_devitalised` is true
## only on a victory where every rival was dissolved.
func register_encounter_end(all_rivals_devitalised: bool) -> void:
	if not all_rivals_devitalised:
		fde_count = 0
		return
	fde_count += 1
	if fde_count >= FDE_THRESHOLD:
		psy_score += 1
		fde_count = 0


# --- Inventory ---


func object_count(object_id: StringName) -> int:
	return inventory.get(object_id, 0)


func has_object(object_id: StringName) -> bool:
	return object_count(object_id) > 0


## Adds to the stack. A `count` of 0 or less is ignored. Returns the new quantity.
func add_object(object_id: StringName, count: int = 1) -> int:
	if count <= 0:
		return object_count(object_id)
	var new_count := object_count(object_id) + count
	inventory[object_id] = new_count
	inventory_changed.emit(object_id, new_count)
	return new_count


## Removes from the stack, all or nothing: fails and changes nothing if fewer are held
## than asked for. An entry reaching 0 is erased rather than kept.
func remove_object(object_id: StringName, count: int = 1) -> bool:
	if count <= 0:
		return false
	var current := object_count(object_id)
	if current < count:
		return false
	var new_count := current - count
	if new_count == 0:
		inventory.erase(object_id)
	else:
		inventory[object_id] = new_count
	inventory_changed.emit(object_id, new_count)
	return true


## Spends one — every object is consumable. False if none is held.
func consume_object(object_id: StringName) -> bool:
	return remove_object(object_id, 1)


# --- Exploration abilities: once per visit, refreshable ---


func mark_exploration_ability_used(id: StringName) -> void:
	used_exploration_abilities[id] = true


func is_exploration_ability_used(id: StringName) -> bool:
	return used_exploration_abilities.get(id, false)


## Refreshes ONE spent exploration ability at random — the litter's Recycle action.
## Returns which, or &"" if none was spent. `rng` is for deterministic tests.
func refresh_random_exploration_ability(rng: RandomNumberGenerator = null) -> StringName:
	var used: Array = used_exploration_abilities.keys()
	if used.is_empty():
		return &""
	var idx := (rng.randi() if rng != null else randi()) % used.size()
	var id: StringName = used[idx]
	used_exploration_abilities.erase(id)
	return id


## Refreshes every spent exploration ability — a refresh crystal.
func refresh_all_exploration_abilities() -> void:
	used_exploration_abilities.clear()


func reset_exploration_abilities() -> void:
	used_exploration_abilities.clear()


## Entering a dungeon: the next encounter is the first of the visit.
func begin_dungeon_visit() -> void:
	first_encounter_pending = true


## Called as an encounter begins. True for the first one of the dungeon visit, and only once.
func take_first_encounter() -> bool:
	var first := first_encounter_pending
	first_encounter_pending = false
	return first


## Wipes the session for a new game.
func reset() -> void:
	main_character = &""
	teammate = &""
	player_name = ""
	psy_score = 0
	fde_count = 0
	encyclopaedia.clear()
	exploration_examine_ifp.clear()
	dungeon_states.clear()
	used_exploration_abilities.clear()
	first_encounter_pending = true
	inventory.clear()
	party_den = {
		PartySlot.MAIN: MAX_DEN,
		PartySlot.TEAMMATE: MAX_DEN,
	}
	party_eth = {
		PartySlot.MAIN: MAX_ETH,
		PartySlot.TEAMMATE: MAX_ETH,
	}
