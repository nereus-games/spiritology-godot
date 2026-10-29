## The encyclopaedia's state, with no UI and no autoload: pages, fragments, and the abilities
## that arranging fragments unlocks. [GameSession] owns one and wraps it with signals.
##
## From the design doc (Game Design / Encyclopaedia):
##   - 1 IFP is 1 % of a page. Every 3 IFP form one TRUE fragment and one PARASITIC one; a page
##     holds 33 true fragments, so its IFP stop at 99.
##   - The last 1 % comes only from a correct, complete assembly ([method mark_assembled]).
##   - 15 correctly arranged fragments reveal the first ability, 30 the second. Once revealed,
##     an ability stays usable even if fragments are later destroyed.
##   - A species has a second, Forlorn page with its own percentage; 15 correctly arranged
##     fragments on it reveal [member SpeciesData.forlorn_ability].
##   - At the start each character has 15 correctly arranged fragments of its own species
##     (30 for a duo of one species).
##
## What the model does NOT know is where a fragment lies: the puzzle owns the geometry. It
## reports how many true fragments are correctly arranged ([method set_arranged]) and what it
## destroyed, and may park its own layout in [member Page.puzzle_state], which the model saves
## without reading.
##
## Not a `class_name` script: the global class cache is only rebuilt by the editor (see
## CLAUDE.md), so [GameSession] preloads this file instead.
extends RefCounted

## IFP that form one true fragment (and one parasitic one).
const IFP_PER_FRAGMENT := 3
## True fragments on a page.
const FRAGMENTS_PER_PAGE := 33
## The most IFP can ever bring a page to; the last % is earned by assembling.
const IFP_CAP := FRAGMENTS_PER_PAGE * IFP_PER_FRAGMENT
## A page's percentage once it has been correctly assembled.
const PAGE_COMPLETE := 100
## Correctly arranged fragments needed for each ability tier, main page: [0] first ability, [1]
## second.
const MAIN_THRESHOLDS: Array[int] = [15, 30]
## The same for the Forlorn page: its single ability.
const FORLORN_THRESHOLDS: Array[int] = [15]
## Correctly arranged fragments each character starts with, from its own species' page.
const STARTING_FRAGMENTS := 15


## One page: a species' main page, or its Forlorn page.
class Page:
	extends RefCounted
	## Info points, 0 to 99, or 100 once assembled.
	var ifp: int = 0
	## Correctly arranged TRUE fragments, as reported by the puzzle.
	var arranged: int = 0
	## Parasitic fragments still lying about.
	var parasitic: int = 0
	## How many of the page's abilities have been revealed. Never goes down.
	var tier: int = 0
	## Whatever the puzzle wants kept between sessions. Opaque to the model; must be JSON-safe.
	var puzzle_state: Dictionary = {}

	func is_assembled() -> bool:
		return ifp >= PAGE_COMPLETE

	## True fragments formed so far.
	func true_fragments() -> int:
		if is_assembled():
			return FRAGMENTS_PER_PAGE
		return mini(ifp / IFP_PER_FRAGMENT, FRAGMENTS_PER_PAGE)

	func to_dict() -> Dictionary:
		return {
			"ifp": ifp,
			"arranged": arranged,
			"parasitic": parasitic,
			"tier": tier,
			"puzzle_state": puzzle_state,
		}

	static func from_dict(d: Dictionary) -> Page:
		var p := Page.new()
		p.ifp = clampi(int(d.get("ifp", 0)), 0, PAGE_COMPLETE)
		p.arranged = clampi(int(d.get("arranged", 0)), 0, p.true_fragments())
		p.parasitic = maxi(int(d.get("parasitic", 0)), 0)
		p.tier = maxi(int(d.get("tier", 0)), 0)
		var state: Variant = d.get("puzzle_state", {})
		p.puzzle_state = state if typeof(state) == TYPE_DICTIONARY else {}
		return p


## species_id -> Page, for the main pages and the Forlorn pages. Pages exist only once touched.
var _main: Dictionary = {}
var _forlorn: Dictionary = {}


func clear() -> void:
	_main.clear()
	_forlorn.clear()


# --- Reading ---


## A page, or null if nothing ever touched it. Do not mutate it from outside the model.
func page(species_id: StringName, forlorn: bool = false) -> Page:
	var pages: Dictionary = _forlorn if forlorn else _main
	return pages.get(species_id)


func ifp(species_id: StringName, forlorn: bool = false) -> int:
	var p := page(species_id, forlorn)
	return p.ifp if p != null else 0


## Entered in the encyclopaedia at all: the main page has at least 1 IFP.
func knows(species_id: StringName) -> bool:
	return ifp(species_id) > 0


## Correctly assembled, hence 100 %.
func is_complete(species_id: StringName, forlorn: bool = false) -> bool:
	return ifp(species_id, forlorn) >= PAGE_COMPLETE


func true_fragments(species_id: StringName, forlorn: bool = false) -> int:
	var p := page(species_id, forlorn)
	return p.true_fragments() if p != null else 0


func parasitic_fragments(species_id: StringName, forlorn: bool = false) -> int:
	var p := page(species_id, forlorn)
	return p.parasitic if p != null else 0


func arranged_fragments(species_id: StringName, forlorn: bool = false) -> int:
	var p := page(species_id, forlorn)
	return p.arranged if p != null else 0


## What the puzzle parked on the page (see [member Page.puzzle_state]); a copy, empty if there is
## none.
func puzzle_state(species_id: StringName, forlorn: bool = false) -> Dictionary:
	var p := page(species_id, forlorn)
	return p.puzzle_state.duplicate(true) if p != null else {}


## IFP a page can still take before the 99 % cap: 0 for a page at the cap or assembled.
func room(species_id: StringName, forlorn: bool = false) -> int:
	return maxi(IFP_CAP - ifp(species_id, forlorn), 0)


## Species whose main page is complete — the damage condition. Keys are species ids.
func completed_species() -> Dictionary:
	var out := {}
	for id in _main:
		if (_main[id] as Page).is_assembled():
			out[id] = true
	return out


## Abilities this species' pages have revealed: its encyclopaedia abilities up to the main
## tier reached, then its Forlorn ability if that page's tier was reached.
func unlocked_abilities(species: SpeciesData) -> Array[StringName]:
	var out: Array[StringName] = []
	if species == null:
		return out
	var main_page := page(species.id)
	var tier := main_page.tier if main_page != null else 0
	for i in mini(tier, species.encyclopaedia_abilities.size()):
		out.append(species.encyclopaedia_abilities[i])
	var forlorn_page := page(species.id, true)
	if forlorn_page != null and forlorn_page.tier >= 1 and species.forlorn_ability != &"":
		out.append(species.forlorn_ability)
	return out


## Every ability the player may use as this species: its origin and also-used abilities, minus
## the ones the encyclopaedia gates (its [member SpeciesData.encyclopaedia_abilities] and its
## [member SpeciesData.forlorn_ability], which the data lists among the origin abilities too)
## unless revealed, plus the revealed ones. Without duplicates, in data order.
##
## A species with nothing gated, such as one that cannot join the duo, keeps every ability.
func usable_abilities(species: SpeciesData) -> Array[StringName]:
	var out: Array[StringName] = []
	if species == null:
		return out
	var gated := {}
	for aid in species.encyclopaedia_abilities:
		gated[aid] = true
	if species.forlorn_ability != &"":
		gated[species.forlorn_ability] = true
	var unlocked := unlocked_abilities(species)
	for aid in unlocked:
		gated.erase(aid)
	for list in [species.origin_abilities, species.also_used_abilities, unlocked]:
		for aid in list:
			if not gated.has(aid) and not (aid in out):
				out.append(aid)
	return out


# --- Writing ---


## Adds IFP, stopping at the 99 % cap, and forms one true and one parasitic fragment per 3
## IFP crossed. Returns what was actually added. `extra_parasites` more wrong fragments come
## each time a batch of fragments forms (PSY above the third rung).
func add_ifp(
	species_id: StringName, amount: int, forlorn: bool = false, extra_parasites: int = 0
) -> int:
	if amount <= 0:
		return 0
	var p := _page_for_write(species_id, forlorn)
	if p.is_assembled():
		return 0
	var added := mini(amount, IFP_CAP - p.ifp)
	if added <= 0:
		return 0
	var before := p.true_fragments()
	p.ifp += added
	var formed := p.true_fragments() - before
	if formed > 0:
		p.parasitic += formed + maxi(extra_parasites, 0)
	return added


## The puzzle's report: how many true fragments are correctly arranged right now. Clamped to
## the fragments that exist. Returns how many ability tiers this newly revealed (0 for none).
func set_arranged(species_id: StringName, forlorn: bool, count: int) -> int:
	var p := _page_for_write(species_id, forlorn)
	p.arranged = clampi(count, 0, p.true_fragments())
	return _refresh_tier(p, forlorn)


## Parks the puzzle's layout on the page, to be saved with it and given back by [method
## puzzle_state]. Opaque to the model; it must be JSON-safe (no Vector2i, no StringName keys).
func set_puzzle_state(species_id: StringName, forlorn: bool, state: Dictionary) -> void:
	_page_for_write(species_id, forlorn).puzzle_state = state.duplicate(true)


## Destroys true fragments (a damaged one hit again by a wrong assembly): the page loses 3 IFP
## each, to be earned back. The arranged count is capped to what is left, so the puzzle should
## report the real figure afterwards. Revealed abilities stay. A complete page cannot lose any.
## Returns how many were destroyed.
func destroy_fragments(species_id: StringName, forlorn: bool, count: int = 1) -> int:
	var p := page(species_id, forlorn)
	if p == null or p.is_assembled() or count <= 0:
		return 0
	var destroyed := mini(count, p.true_fragments())
	p.ifp -= destroyed * IFP_PER_FRAGMENT
	p.arranged = mini(p.arranged, p.true_fragments())
	return destroyed


## Parasitic fragments that disappeared (a wrong assembly). Returns how many were removed.
func remove_parasitic(species_id: StringName, forlorn: bool, count: int = 1) -> int:
	var p := page(species_id, forlorn)
	if p == null or count <= 0:
		return 0
	var removed := mini(count, p.parasitic)
	p.parasitic -= removed
	return removed


## A correct, complete assembly: the page goes from 99 to 100 %, the remaining parasitic
## fragments vanish, every true fragment counts as arranged. Refused (false) unless the page is
## at 99 % with all 33 true fragments reported as arranged via [method set_arranged] — the
## model does not take the puzzle's word that it is finished without those two facts.
func mark_assembled(species_id: StringName, forlorn: bool = false) -> bool:
	var p := page(species_id, forlorn)
	if p == null or p.is_assembled():
		return false
	if p.ifp < IFP_CAP or p.arranged < FRAGMENTS_PER_PAGE:
		return false
	p.ifp = PAGE_COMPLETE
	p.parasitic = 0
	_refresh_tier(p, forlorn)
	return true


## The start of the game: each character has [constant STARTING_FRAGMENTS] correctly arranged
## fragments of its own species' page, 30 for two of the same species. Their IFP (3 per
## fragment) are credited too, since a fragment is what 3 IFP are. Monotonic and idempotent: a
## page already beyond the grant is left alone. Returns the species ids whose page changed.
func grant_starting_duo(main_species: StringName, teammate_species: StringName) -> Array:
	var counts := {}
	for id in [main_species, teammate_species]:
		if id != &"":
			counts[id] = int(counts.get(id, 0)) + 1
	var changed := []
	for id in counts:
		var p := _page_for_write(id, false)
		if p.is_assembled():
			continue
		var target := mini(STARTING_FRAGMENTS * int(counts[id]), FRAGMENTS_PER_PAGE)
		var before := [p.ifp, p.arranged, p.tier]
		p.ifp = maxi(p.ifp, target * IFP_PER_FRAGMENT)
		p.arranged = maxi(p.arranged, target)
		_refresh_tier(p, false)
		if before != [p.ifp, p.arranged, p.tier]:
			changed.append(id)
	return changed


# --- Saving ---


func to_dict() -> Dictionary:
	var out := {"main": {}, "forlorn": {}}
	for id in _main:
		out["main"][String(id)] = (_main[id] as Page).to_dict()
	for id in _forlorn:
		out["forlorn"][String(id)] = (_forlorn[id] as Page).to_dict()
	return out


func from_dict(d: Dictionary) -> void:
	clear()
	for key in d.get("main", {}):
		_main[StringName(key)] = Page.from_dict(d["main"][key])
	for key in d.get("forlorn", {}):
		_forlorn[StringName(key)] = Page.from_dict(d["forlorn"][key])


## Saves from before pages existed only held species -> IFP. Their fragments are formed from the
## IFP; nothing counts as arranged (the starting duo grant restores the duo's own).
func from_legacy_ifp(d: Dictionary) -> void:
	clear()
	for key in d:
		var p := Page.new()
		p.ifp = clampi(int(d[key]), 0, PAGE_COMPLETE)
		p.parasitic = 0 if p.is_assembled() else p.true_fragments()
		_main[StringName(key)] = p


# --- Internals ---


func _page_for_write(species_id: StringName, forlorn: bool) -> Page:
	var pages: Dictionary = _forlorn if forlorn else _main
	if not pages.has(species_id):
		pages[species_id] = Page.new()
	return pages[species_id]


## Raises the page's tier to what its arranged count earns. Returns the number of new tiers.
func _refresh_tier(p: Page, forlorn: bool) -> int:
	var thresholds: Array[int] = FORLORN_THRESHOLDS if forlorn else MAIN_THRESHOLDS
	var earned := 0
	for t in thresholds:
		if p.arranged >= t:
			earned += 1
	if earned <= p.tier:
		return 0
	var gained := earned - p.tier
	p.tier = earned
	return gained
