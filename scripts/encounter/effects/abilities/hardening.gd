## Hardening — firulis · Crystal · normal · [damage reduction/immunity]
## MECHANIC: a target on the team becomes immune to Crystal damage and has all damage it takes
## halved until its next turn, and (the doc's "info penalty on Talk") what its Talk yields in
## IFP is cut by [member BalanceData.hardening_talk_penalty] through its next turn.
extends AbilityScript

const NextTurnModifiers := preload("res://scripts/encounter/effects/next_turn_modifiers.gd")


func execute(ctx: EncounterContext) -> void:
	var t = ctx.user
	ctx.grant_immunity(t, [GameEnums.Energy.CRYSTAL])
	ctx.scale_all_damage(t, 0.5)
	# Two turns of the user's: a penalty that ended as its next turn began could never touch the
	# Talk it is meant to weigh on. The doc does not time it; this is the least surprising reading.
	NextTurnModifiers.scale_talk_info(ctx, t, 1.0 - BalanceData.current().hardening_talk_penalty, 2)
