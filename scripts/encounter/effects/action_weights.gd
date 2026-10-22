## What the abilities that make rivals Talk, Meditate or use objects "more often" ask for.
##
## Kept out of [EncounterContext] on purpose: it is at its limit of public methods, and this is
## one small, self-contained rule. Everything is anchored to the ability's user and lasts until
## its next turn, unless `turns` says otherwise ([constant EncounterIndividual.FOR_ENCOUNTER]
## for the rest of the encounter). The weight itself lives on the individual, see
## [method EncounterIndividual.add_action_weight]; the choice it changes is made by [AutoAgent].

## Makes `target` likelier to pick the base action `kind` by `bonus`, a probability added on top
## of what it already has. A `focus` aims the Talk at someone. Logs it through the context.
static func weigh(
	ctx: EncounterContext,
	target,
	kind: int,
	bonus: float,
	turns := EncounterIndividual.UNTIL_NEXT_TURN,
	focus = null
) -> void:
	if not (target is EncounterIndividual) or target.is_dissolved():
		return
	var focus_who: EncounterIndividual = focus if focus is EncounterIndividual else null
	var anchor: EncounterIndividual = ctx.user if ctx.user is EncounterIndividual else null
	target.add_action_weight(kind, bonus, anchor, turns, focus_who)
	var key := "LOG_WEIGHT_TALK"
	if kind == EncounterAction.Kind.MEDITATE:
		key = "LOG_WEIGHT_MEDITATE"
	elif kind == EncounterAction.Kind.USE_OBJECT:
		key = "LOG_WEIGHT_OBJECT"
	ctx.note(TranslationServer.translate(key) % target.display_name())


## The opponents sharing the user's origin, its Spiricosm.
static func same_origin_opponents(ctx: EncounterContext) -> Array:
	var out: Array = []
	for f in ctx.opponents():
		if f.species and ctx.user.species and f.species.spiricosm == ctx.user.species.spiricosm:
			out.append(f)
	return out
