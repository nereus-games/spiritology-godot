## Glorification — malcouli · [change weakness, recover ETH]
## MECHANIC: the user takes on the target's weakness (approximated across the 3) and gains ETH:
## a little from a teammate, more from a rival of the same origin, more still from a rival of a
## different one. Losing that ETH if the target then hurts it is a TODO.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var t = ctx.primary()
	if t == null:
		return
	ctx.set_weakness(ctx.user, ctx.weakness_of(t))
	var amount: int
	if t.is_player == ctx.user.is_player:
		amount = ctx.dmg(&"small")
	elif t.species and ctx.user.species and t.species.spiricosm == ctx.user.species.spiricosm:
		amount = ctx.dmg(&"normal")
	else:
		amount = ctx.dmg(&"big")
	ctx.recover_eth(ctx.user, amount)
