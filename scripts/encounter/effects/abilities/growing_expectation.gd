## Growing Expectation — sénskor · Crystal · a lot · [change weakness, recover DEN]
## MECHANIC: the user gains X DEN and its weakness becomes Heat; the targeted rival's weakness
## becomes Crystal.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	ctx.recover_den(ctx.user, ctx.dmg(&"normal"))
	ctx.set_weakness(ctx.user, GameEnums.Energy.HEAT)
	var t = ctx.primary()
	if t:
		ctx.set_weakness(t, GameEnums.Energy.CRYSTAL)
