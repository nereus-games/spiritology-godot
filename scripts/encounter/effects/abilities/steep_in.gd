## Steep in — vérnal · Variable · mini · [change weakness, examine bonus]
## MECHANIC: the ability's energy is the user's current weakness. The user Examines the target,
## then its own weakness becomes the target's.
##
## A plain Examine ([method ExamineYield.examine], no extra info bonus: the text gives none), made
## before the weakness changes hands.
extends AbilityScript

const ExamineYield := preload("res://scripts/encounter/effects/examine_yield.gd")


func execute(ctx: EncounterContext) -> void:
	ctx.set_energy(ctx.weakness_of(ctx.user))
	var t = ctx.primary()
	if t:
		ExamineYield.examine(ctx, t, 0)
		ctx.set_weakness(ctx.user, ctx.weakness_of(t))
