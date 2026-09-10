## Reactive Depreciation — fonéchal · normal · [ETH loss, limit actions]
## MECHANIC: requires a turn to have passed and the user to have already acted. The last rival
## that used an action or energy different from the user's loses X ETH, and if it is then out of
## ETH it loses an action next turn. Picking that rival from history is approximated by a random
## one.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var t = ctx.random_opponent()
	if t == null:
		return
	ctx.drain_eth(t, ctx.dmg(&"small"))
	if t.eth == 0:
		ctx.limit_actions(t, 1)
