## The whole mechanic of ONE ability.
##
## Every ability has its own script in `effects/abilities/<id>.gd`, with its mechanic
## quoted from the design doc in the docstring. An implemented one overrides
## [method execute] with that mechanic — usually conditional on targets, weaknesses, turn
## order or the UI — composing [AbilityEffect] bricks or calling [EncounterContext]
## directly.
##
## Until it is written, the default below stands in: run the generic effects derived from
## the ability's tags. That is a scaffold, not the mechanic, and a script still carrying
## `# @unimplemented` on its first line is one of those.
class_name AbilityScript
extends RefCounted


## Override with the ability's real mechanic.
func execute(ctx: EncounterContext) -> void:
	for effect in EffectCatalog.tag_effects(ctx.ability.tags):
		effect.execute(ctx)
