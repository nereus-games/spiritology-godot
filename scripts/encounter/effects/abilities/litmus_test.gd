## Litmus Test — granop · [limit actions, recover ETH]
## MECHANIC: the last 2 abilities the target used become unusable to it for the rest of the
## encounter; the user and the target each gain X ETH if their origins differ.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var t = ctx.primary()
	if t == null:
		return
	ctx.restrict_to(t, ["LOG_RESTRICT_EXCEPT_LAST_TWO_ABILITIES"])
	if t.species and ctx.user.species and t.species.spiricosm != ctx.user.species.spiricosm:
		ctx.recover_eth(ctx.user, ctx.dmg(&"small"))
		ctx.recover_eth(t, ctx.dmg(&"small"))
