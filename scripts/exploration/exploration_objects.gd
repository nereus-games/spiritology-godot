## Usage des objets d'inventaire EN EXPLORATION.
##
## Mappe l'[enum GameEnums.ObjectEffect] d'un [ObjectData] vers les primitives de
## [ExplorationContext], et consomme l'objet en cas de succès. Les effets réservés à la
## rencontre (FLEE_ENCOUNTER) ne sont pas utilisables ici.
##
## Pas de `class_name` (piège du cache CLI) : référencé par `preload`. Référence les autoloads
## GameData / GameSession (OK en jeu ; charger au runtime dans les tests).
extends RefCounted

## DEN rendu par défaut si l'objet HEAL_DEN n'a pas de magnitude chiffrée (placeholder).
const DEFAULT_HEAL := 20

## Effets utilisables pendant l'exploration.
static func usable_in_exploration(effect: int) -> bool:
	return effect in [
		GameEnums.ObjectEffect.CURE_POISON,
		GameEnums.ObjectEffect.HEAL_DEN,
		GameEnums.ObjectEffect.AVOID_PURSUIT,
		GameEnums.ObjectEffect.DISGUISE,
	]

## Utilise un objet en exploration : applique son effet via `ctx` et le consomme si l'effet
## a bien été appliqué. Retourne true en cas de succès.
static func use_object(object_id: StringName, ctx) -> bool:
	var data: ObjectData = GameData.object(object_id)
	if data == null or not GameSession.has_object(object_id):
		return false
	if not _apply(data, ctx):
		return false
	GameSession.consume_object(object_id)
	return true

static func _apply(data: ObjectData, ctx) -> bool:
	match data.effect:
		GameEnums.ObjectEffect.CURE_POISON:
			ctx.cure_poison()
			return true
		GameEnums.ObjectEffect.HEAL_DEN:
			ctx.heal_duo(maxi(data.magnitude, DEFAULT_HEAL))
			return true
		GameEnums.ObjectEffect.AVOID_PURSUIT:
			ctx.avoid_pursuit(maxi(data.duration_moves, 1))
			return true
		GameEnums.ObjectEffect.DISGUISE:
			ctx.avoid_pursuit(maxi(data.duration_moves, 1), data.species_id)
			return true
		_:
			return false
