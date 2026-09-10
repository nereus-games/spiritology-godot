## Love Bombing — forlorn yadol · normal · [ETH loss, change weakness]
## MECHANIC: the targeted rival loses X ETH, and as much again per ally of the user sharing the
## user's weakness; if the target is then out of ETH and alone, it takes the user's weakness.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var t = ctx.primary()
	if t == null:
		return
	var uw := ctx.weakness_of(ctx.user)
	var extra := ctx.allies().filter(func(a): return ctx.weakness_of(a) == uw).size()
	ctx.drain_eth(t, ctx.dmg(&"small") * (1 + extra))
	if t.eth == 0 and ctx.opponents().size() == 1:
		ctx.set_weakness(t, uw)
