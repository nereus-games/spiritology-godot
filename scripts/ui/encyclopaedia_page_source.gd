## What an encyclopaedia page says about a species, gathered in one place.
##
## The page view reads ONLY this script, never [SpeciesData] or [GameSession] directly, so that
## the fragment model (which decides which abilities are unlocked and what the completion is)
## can replace the two seams below without the view noticing.
##
## No `class_name` (the CLI class-cache trap): referenced by `preload`.
extends RefCounted

## Fragments to arrange correctly for each encyclopaedia ability, in order. Source: design doc,
## Encyclopaedia / Filling the Encyclopaedia.
const FRAGMENTS_FOR_ABILITY: Array[int] = [15, 30]


## Everything the page shows, as a Dictionary. Keys: `species` ([SpeciesData]), `ifp`,
## `completion`, `weaknesses` (three [enum GameEnums.Energy], in turn-order position), `talent`
## ([TalentData] or null), `abilities` (an array of `{id, unlocked, fragments}`) and `loot`.
static func build(species_id: StringName) -> Dictionary:
	var sp: SpeciesData = GameData.species(species_id)
	var unlocked := unlocked_abilities(species_id)
	var abilities: Array = []
	for i in sp.encyclopaedia_abilities.size():
		var ability_id: StringName = sp.encyclopaedia_abilities[i]
		abilities.append(
			{
				"id": ability_id,
				"unlocked": ability_id in unlocked,
				"fragments": FRAGMENTS_FOR_ABILITY[mini(i, FRAGMENTS_FOR_ABILITY.size() - 1)],
			}
		)
	return {
		"species": sp,
		"ifp": int(GameSession.encyclopaedia_ifp.get(species_id, 0)),
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


## The page's completion, in percent.
##
## SEAM: 1 IFP is 1 % of a page, so today it is the IFP. With fragments it becomes the share of
## the page correctly assembled (the last percent coming from the full assembly).
static func completion_percent(species_id: StringName) -> int:
	return clampi(int(GameSession.encyclopaedia_ifp.get(species_id, 0)), 0, 100)


## The encyclopaedia abilities of the species that are revealed and usable.
##
## SEAM: nothing records which fragments are correctly arranged yet, so none is. The doc has the
## first ability at 15 correct fragments, the second at 30, and each player character starting
## with 15 of its own species' — all of it belongs to the fragment model, and to nowhere else.
## This is deliberately NOT derived from the IFP: the IFP is not the arranged fragments.
static func unlocked_abilities(_species_id: StringName) -> Array[StringName]:
	return []
