## Libation — mastél · Fluid · mini · [change weakness, recover DEN]
## MECHANIC: the user and a targeted rival both gain X DEN, and their weakness becomes Fluid for
## this turn and the next — the persistence is approximated to the round.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	ctx.recover_den(ctx.user, ctx.dmg(&"normal"))
	ctx.set_weakness(ctx.user, GameEnums.Energy.FLUID)
	var t = ctx.primary()
	if t:
		ctx.recover_den(t, ctx.dmg(&"normal"))
		ctx.set_weakness(t, GameEnums.Energy.FLUID)
