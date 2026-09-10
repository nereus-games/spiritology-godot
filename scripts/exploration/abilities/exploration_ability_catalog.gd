## Catalogue of exploration ability effects, the counterpart of [EffectCatalog].
##
## A static utility: `script_for(id)` loads `impl/<id>.gd` when it exists, and the neutral base
## effect otherwise; `known_for_duo()` lists the current duo's exploration abilities.
##
## No `class_name` (the CLI class-cache trap): referenced by `preload`. References the GameData
## and GameSession autoloads and the GameEnums enum — fine in game, but tests have to load them
## at runtime.
extends RefCounted

const _BASE := preload("res://scripts/exploration/abilities/exploration_ability.gd")

## Exploration abilities a mechanism already handles CONTEXTUALLY — the cracked wall offers
## "cross" itself — and which must not be offered a second time as a standalone action.
const _CONTEXTUAL: Array[StringName] = [&"cranny_crossing"]

## A TEST/DEV hook: exploration abilities granted to the duo regardless of species, filled in by
## the test scenarios. Merged into [method known_for_duo].
static var dev_granted: Array[StringName] = []


## An effect instance for an exploration ability: the dedicated subclass, or the neutral base.
static func script_for(id: StringName):
	var path := "res://scripts/exploration/abilities/impl/%s.gd" % id
	if ResourceLoader.exists(path):
		return load(path).new()
	return _BASE.new()


## The duo's known exploration abilities: the union of origin, also_used and encyclopaedia
## across both members, filtered to type EXPLORATION. Contextual abilities, such as the cracked
## wall's, are excluded.
static func known_for_duo() -> Array:
	var ids := {}
	for aid in dev_granted:
		if not (aid in _CONTEXTUAL):
			ids[aid] = true
	for member in [GameSession.main_character, GameSession.teammate]:
		if member == &"":
			continue
		var sp: SpeciesData = GameData.species(member)
		if sp == null:
			continue
		for arr in [sp.origin_abilities, sp.also_used_abilities, sp.encyclopaedia_abilities]:
			for aid in arr:
				if aid in _CONTEXTUAL:
					continue
				var ab: AbilityData = GameData.ability(aid)
				if ab != null and ab.type == GameEnums.AbilityType.EXPLORATION:
					ids[aid] = true
	return ids.keys()
