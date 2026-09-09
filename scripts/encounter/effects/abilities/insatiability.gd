## Insatiability — kalilk · Fluid · [damage, recover DEN]
## MÉCANIQUE : le user prélève X DEN à tous les autres individus (dégâts + soin de soi),
## puis perd tout son ETH.
extends AbilityScript

func execute(ctx: EncounterContext) -> void:
	var stolen := 0
	for o in ctx.others():
		var amt := ctx.dmg(&"small")
		ctx.deal_damage(o, amt)
		stolen += amt
	ctx.recover_den(ctx.user, stolen)
	ctx.drain_eth(ctx.user, ctx.user.eth)
