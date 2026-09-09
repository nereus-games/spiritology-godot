## Hypnotize — jézal · Fluid · [ETH loss, limit actions]
## MÉCANIQUE : le rival ciblé perd une action au hasard à son prochain tour et perd X ETH.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var t = ctx.primary()
	if t:
		ctx.drain_eth(t, ctx.dmg(&"small"))
		ctx.limit_actions(t, 1)
