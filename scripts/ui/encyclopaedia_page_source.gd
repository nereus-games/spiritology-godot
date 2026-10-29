## What an encyclopaedia page says about a species, gathered in one place.
##
## The page view reads ONLY this script, never [SpeciesData] or [GameSession] directly, so that
## the fragment model can change what feeds the two functions below without the view noticing.
##
## No `class_name` (the CLI class-cache trap): referenced by `preload`.
extends RefCounted

## Fragments to arrange correctly for each encyclopaedia ability, in order. Source: design doc,
## Encyclopaedia / Filling the Encyclopaedia.
const FRAGMENTS_FOR_ABILITY: Array[int] = [15, 30]
## The same for the Forlorn page's single ability.
const FORLORN_FRAGMENTS := 15


## Everything the page shows, as a Dictionary. Keys: `species` ([SpeciesData]), `ifp`,
## `completion`, `weaknesses` (three [enum GameEnums.Energy], in turn-order position), `talent`
## ([TalentData] or null), `abilities` (an array of `{id, unlocked, fragments}`) and `loot`.
static func build(species_id: StringName) -> Dictionary:
	var sp: SpeciesData = GameData.species(species_id)
	var unlocked := unlocked_abilities(species_id)
	var abilities: Array = []
	for i in sp.encyclopaedia_abilities.size():
		var ability_id: StringName = sp.encyclopaedia_abilities[i]
		(
			abilities
			. append(
				{
					"id": ability_id,
					"unlocked": ability_id in unlocked,
					"fragments": FRAGMENTS_FOR_ABILITY[mini(i, FRAGMENTS_FOR_ABILITY.size() - 1)],
				}
			)
		)
	return {
		"species": sp,
		"ifp": GameSession.page_ifp(species_id),
		"completion": completion_percent(species_id),
		"weaknesses":
		[
			sp.weakness_for(GameEnums.TurnPosition.FIRST),
			sp.weakness_for(GameEnums.TurnPosition.MIDDLE),
			sp.weakness_for(GameEnums.TurnPosition.LAST),
		],
		"talent": GameData.talent(sp.talent),
		"abilities": abilities,
		"loot": sp.loot,
	}


## What the Forlorn tab of a species shows. Keys: `species` ([SpeciesData]), `ifp`, `completion`,
## `ability` (the Forlorn ability id, or &"" if the species has none), `unlocked` (whether the
## Forlorn page has revealed it), `fragments` (arranged fragments it takes), and `open` (whether
## the ordinary page is complete, which is when Forlorn rivals start to fill this page).
static func build_forlorn(species_id: StringName) -> Dictionary:
	var sp: SpeciesData = GameData.species(species_id)
	return {
		"species": sp,
		"ifp": GameSession.page_ifp(species_id, true),
		"completion": clampi(GameSession.page_ifp(species_id, true), 0, 100),
		"ability": sp.forlorn_ability,
		"unlocked":
		sp.forlorn_ability != &"" and sp.forlorn_ability in GameSession.unlocked_abilities(species_id),
		"fragments": FORLORN_FRAGMENTS,
		"open": GameSession.is_page_complete(species_id),
	}


## The page's completion, in percent.
##
## 1 IFP is 1 % of a page, and the model holds the last percent back until the page is fully
## assembled, so this is the model's percentage.
static func completion_percent(species_id: StringName) -> int:
	return clampi(GameSession.page_ifp(species_id), 0, 100)


## The encyclopaedia abilities of the species that are revealed, as the fragment model has it.
static func unlocked_abilities(species_id: StringName) -> Array[StringName]:
	var revealed := GameSession.unlocked_abilities(species_id)
	var result: Array[StringName] = []
	for ability_id in GameData.species(species_id).encyclopaedia_abilities:
		if ability_id in revealed:
			result.append(ability_id)
	return result


## Whether the page has fragments to put on the assembly desk, true or parasitic: the page
## offers the desk only then. The player is not told which are which, so neither is the view.
static func can_assemble(species_id: StringName, forlorn: bool = false) -> bool:
	return (
		GameSession.true_fragments(species_id, forlorn) > 0
		or GameSession.parasitic_fragments(species_id, forlorn) > 0
	)
