## Self-Forgiveness — érdouss · Arcane · single use · [change weakness, recover ETH]
## MECHANIC: the user regains X ETH, loses its weakness, and cannot lose ETH until the next
## turn; if it uses an ability next turn, it pays no ETH cost for it.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	ctx.recover_eth(ctx.user, ctx.dmg(&"normal"))
	ctx.remove_weakness(ctx.user)
	ctx.lock_eth(ctx.user)
	# TODO: make next turn's ability free, ignoring its ETH cost.
