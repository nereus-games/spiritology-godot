## Growing Expectation — sénskor · Crystal · a lot · [change weakness, recover DEN]
## MÉCANIQUE : le user gagne X DEN, sa faiblesse devient Chaleur ;
## la faiblesse du rival ciblé devient Cristal.
extends AbilityScript

func execute(ctx: EncounterContext) -> void:
	ctx.recover_den(ctx.user, ctx.dmg(&"normal"))
	ctx.set_weakness(ctx.user, GameEnums.Energy.HEAT)
	var t = ctx.primary()
	if t:
		ctx.set_weakness(t, GameEnums.Energy.CRYSTAL)
