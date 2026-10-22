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


## Whether the ability takes its own user out of the encounter — Ghosting, Opening up Closing.
## Read by [AutoAgent], which is not meant to leave on its own; the effect itself still goes
## through [method EncounterContext.flee].
func takes_user_away() -> bool:
	return false


## Override for an ability that REACTS: one whose [method execute] calls
## [method EncounterContext.watch_reactions], and which is then asked about everything that
## happens until its user's next turn.
##
## `ctx` is the ability's own context, its user being the one who used the ability and its
## targets the individual who acted; `event` says what happened — see the event class's
## questions. Nothing is required of it: most events do not concern the ability, and it simply
## returns.
##
## A reaction cannot set off further reactions through the damage it deals.
func react(_ctx: EncounterContext, _event) -> void:
	pass


## Override for an ability the doc makes usable only under a condition ("usable only if…").
## `ctx` is the one the ability would run in, so the condition may ask the encounter history. The
## menu greys the ability out, and [AutoAgent] leaves it alone, while this is false.
func is_usable(_ctx: EncounterContext) -> bool:
	return true


## Override for an ability that RECURS: one whose [method execute] calls
## [method EncounterContext.recur_each_turn] on its target. This runs at the start of each of the
## bearer's turns, for as long as the effect lasts. `ctx` is the ability's own context, its user
## being whoever applied it and its only target the bearer. Like a reaction, it cannot set off
## reactions through the damage it deals.
func recur(_ctx: EncounterContext) -> void:
	pass


## Override for a recurring ability that the bearer can shake off by Meditating: undo whatever
## else the ability left on it (through `ctx`, as in [method recur]) and return true. Returning
## false, as the default does, leaves the effect running.
func on_meditated(_ctx: EncounterContext) -> bool:
	return false


## Override with the ability's real mechanic.
func execute(ctx: EncounterContext) -> void:
	for effect in EffectCatalog.tag_effects(ctx.ability.tags):
		effect.execute(ctx)
