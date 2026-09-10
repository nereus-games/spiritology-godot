## Blockage — spodra · Fluid · mini · usage unique · [ETH loss, change weakness]
## MECHANIC: the target has no weakness until its next turn; if it is a teammate or a rival, it
## also loses X ETH.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var t = ctx.primary()
	if t == null:
		return
	ctx.remove_weakness(t)
	if t != ctx.user:
		ctx.drain_eth(t, ctx.dmg(&"small"))
