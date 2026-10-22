## Priming — fopin · Variable · medium · [change next TO, change weakness, immunity]
## MECHANIC: a targeted teammate moves first next turn and takes this ability's energy as its
## weakness; until the user's next turn, the teammates' damage steps up one tier
## (mini to small to normal to big) and they get more info.
##
## The tier step is a modifier on the teammates, the user excepted ("teammates" is
## [method EncounterContext.allies]) and applied to the base damage of whatever they deal.
## "They get more info" raises the IFP of the teammates' Examines until the user's next turn, by
## `EXAMINE_BONUS_POINTS` points of info bonus (`examine_yield.gd`); the doc gives no figure.
extends AbilityScript

const NextTurnModifiers := preload("res://scripts/encounter/effects/next_turn_modifiers.gd")
const ExamineYield := preload("res://scripts/encounter/effects/examine_yield.gd")

## Placeholder: "more info", with no amount in the doc.
const EXAMINE_BONUS_POINTS := 2


func execute(ctx: EncounterContext) -> void:
	var t = ctx.random_of(ctx.allies())
	if t:
		ctx.move_to_first(t)
		ctx.set_weakness(t, ctx.energy())
	for ally in ctx.allies():
		NextTurnModifiers.step_up_damage(ctx, ally)
		ExamineYield.boost(ctx, ally, EXAMINE_BONUS_POINTS)
