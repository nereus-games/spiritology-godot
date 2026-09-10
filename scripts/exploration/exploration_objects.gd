## Using inventory objects DURING EXPLORATION.
##
## Maps an [ObjectData]'s [enum GameEnums.ObjectEffect] onto [ExplorationContext]'s primitives,
## and consumes the object on success. Encounter-only effects, such as FLEE_ENCOUNTER, are not
## usable here.
##
## No `class_name` (the CLI class-cache trap): referenced by `preload`. References the GameData
## and GameSession autoloads — fine in game, but tests have to load them at runtime.
extends RefCounted

## DEN given back when a HEAL_DEN object carries no magnitude. Placeholder.
const DEFAULT_HEAL := 20


static func usable_in_exploration(effect: int) -> bool:
	return (
		effect
		in [
			GameEnums.ObjectEffect.CURE_POISON,
			GameEnums.ObjectEffect.HEAL_DEN,
			GameEnums.ObjectEffect.AVOID_PURSUIT,
			GameEnums.ObjectEffect.DISGUISE,
		]
	)


## Uses an object during exploration: applies its effect through `ctx` and consumes it only if
## the effect actually landed. Returns true on success.
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
