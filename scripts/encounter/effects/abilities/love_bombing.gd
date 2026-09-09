## Love Bombing — forlorn yadol · normal · [ETH loss, change weakness]
## MÉCANIQUE : le rival ciblé perd X ETH, et encore autant par allié du user partageant la
## faiblesse du user ; si la cible n'a alors plus d'ETH et est seule, elle prend la faiblesse du user.
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
