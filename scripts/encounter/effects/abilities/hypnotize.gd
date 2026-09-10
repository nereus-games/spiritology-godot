## Hypnotize — jézal · Fluid · [ETH loss, limit actions]
## MECHANIC: the targeted rival loses a random action on its next turn, and loses X ETH.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var t = ctx.primary()
	if t:
		ctx.drain_eth(t, ctx.dmg(&"small"))
		ctx.limit_actions(t, 1)
