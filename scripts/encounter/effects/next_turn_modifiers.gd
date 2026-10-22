## What an ability does to the NEXT action of an individual — the ability that costs nothing, the
## Talk that yields as much as an Examine, damage a tier higher, a Talk that yields less.
##
## Kept out of [EncounterContext] on purpose: that class is already the largest in the project,
## and these four are one family. The state itself lives on [EncounterIndividual] (see its
## "Next-turn modifiers" block); the encounter reads it in [method EncounterManager._resolve_talk]
## and [method EncounterManager._resolve_ability], and [method EncounterContext.deal_damage] reads
## the tier steps. An ability calls these with its own context.
##
## Static functions, used as `const NextTurnModifiers := preload(...)` — no `class_name`, see
## CLAUDE.md.
extends RefCounted


## The target's next ability costs no ETH, if it uses one on its next turn.
static func make_next_ability_free(ctx: EncounterContext, target) -> void:
	if target is EncounterIndividual:
		target.grant_free_next_ability()
	ctx.note(_tr("LOG_NEXT_ABILITY_FREE") % _name(target))


## The target's next Talk yields as much IFP as an Examine.
static func make_next_talk_count_as_examine(ctx: EncounterContext, target) -> void:
	if target is EncounterIndividual:
		target.grant_talk_as_examine()
	ctx.note(_tr("LOG_NEXT_TALK_AS_EXAMINE") % _name(target))


## What the target deals goes up one damage tier until the user's next turn.
static func step_up_damage(ctx: EncounterContext, target) -> void:
	if target is EncounterIndividual:
		target.step_up_damage_tier(1, ctx.user)
	ctx.note(_tr("LOG_DAMAGE_STEPS_UP") % _name(target))


## Multiplies the IFP the target's Talk yields until the user's next turn, or for `turns` of it.
static func scale_talk_info(
	ctx: EncounterContext, target, factor: float, turns := EncounterIndividual.UNTIL_NEXT_TURN
) -> void:
	if target is EncounterIndividual:
		target.scale_talk_info(factor, ctx.user, turns)
	ctx.note(_tr("LOG_TALK_INFO_FACTOR") % [_name(target), factor])


static func _name(target) -> String:
	return target.display_name() if target is EncounterIndividual else str(target)


static func _tr(key: String) -> String:
	return String(TranslationServer.translate(key))
