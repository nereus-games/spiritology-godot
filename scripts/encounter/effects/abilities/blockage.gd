## Blockage — spodra · Fluid · mini · usage unique · [ETH loss, change weakness]
## MÉCANIQUE : la cible n'a plus de faiblesse jusqu'à son prochain tour ;
## si c'est un coéquipier ou un rival, elle perd X ETH.
extends AbilityScript

func execute(ctx: EncounterContext) -> void:
	var t = ctx.primary()
	if t == null:
		return
	ctx.remove_weakness(t)
	if t != ctx.user:
		ctx.drain_eth(t, ctx.dmg(&"small"))
