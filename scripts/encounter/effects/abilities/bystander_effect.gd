## Bystander Effect — ravbak · Heat · medium · [change weakness, examine bonus, limit actions]
## MECHANIC: the user's weakness becomes Crystal and one of its actions, drawn at random, is
## unavailable next turn; the other individuals get far more information out of Talk and
## Examine until the user's next turn.
##
## "Far more" is `EXAMINE_BONUS_POINTS` of info bonus on their Examines (`examine_yield.gd`) and
## the same factor on the IFP their Talks yield, both until the user's next turn. The "others" are
## everyone but the user, rivals included; a rival earns no IFP, so only the user's teammate gains.
extends AbilityScript

const ExamineYield := preload("res://scripts/encounter/effects/examine_yield.gd")
const NextTurnModifiers := preload("res://scripts/encounter/effects/next_turn_modifiers.gd")

## Placeholder: "far more", with no figure in the doc. 5 points are +50 % at the current step.
const EXAMINE_BONUS_POINTS := 5


func execute(ctx: EncounterContext) -> void:
	ctx.set_weakness(ctx.user, GameEnums.Energy.CRYSTAL)
	ctx.limit_actions(ctx.user, 1)
	for o in ctx.others():
		ExamineYield.boost(ctx, o, EXAMINE_BONUS_POINTS)
		NextTurnModifiers.scale_talk_info(ctx, o, ExamineYield.factor_for(EXAMINE_BONUS_POINTS))
