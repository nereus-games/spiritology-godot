## Catalogue des effets de capacités d'exploration (équivalent de [EffectCatalog]).
##
## Utilitaire statique : `script_for(id)` charge `impl/<id>.gd` s'il existe (sinon l'effet de
## base neutre), et `known_for_duo()` liste les capacités d'exploration du duo courant.
##
## Pas de `class_name` (piège du cache CLI) : référencé par `preload`. Référence les autoloads
## GameData / GameSession / l'enum GameEnums (OK en jeu ; charger au runtime dans les tests).
extends RefCounted

const _BASE := preload("res://scripts/exploration/abilities/exploration_ability.gd")

## Capacité d'exploration gérée de façon CONTEXTUELLE par un mécanisme (le mur fissuré offre
## déjà « traverser ») : à ne pas re-proposer comme action de capacité autonome.
const _CONTEXTUAL: Array[StringName] = [&"cranny_crossing"]

## Hook de TEST/DEV : capacités d'exploration accordées au duo indépendamment de l'espèce
## (rempli par les scénarios de test). Fusionné dans [method known_for_duo].
static var dev_granted: Array[StringName] = []


## Instance d'effet pour une capacité d'exploration (sous-classe dédiée ou base neutre).
static func script_for(id: StringName):
	var path := "res://scripts/exploration/abilities/impl/%s.gd" % id
	if ResourceLoader.exists(path):
		return load(path).new()
	return _BASE.new()


## Capacités d'exploration connues du duo (union origin/also_used/encyclopaedia des deux
## membres, filtrée au type EXPLORATION). Exclut les capacités contextuelles (mur fissuré).
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
