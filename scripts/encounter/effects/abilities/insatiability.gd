## Insatiability — kalilk · Fluid · [damage, recover DEN]
## MECHANIC: the user drains X DEN from every other individual — damage to them, healing for
## itself — then loses all its ETH.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var stolen := 0
	for o in ctx.others():
		var amt := ctx.dmg(&"small")
		ctx.deal_damage(o, amt)
		stolen += amt
	ctx.recover_den(ctx.user, stolen)
	ctx.drain_eth(ctx.user, ctx.user.eth)
