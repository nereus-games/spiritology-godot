## Self-Forgiveness — érdouss · Arcane · usage unique · [change weakness, recover ETH]
## MÉCANIQUE : le user regagne X ETH, perd sa faiblesse, ne peut plus perdre d'ETH jusqu'au
## prochain tour ; s'il utilise une capacité au prochain tour, il n'en paie pas le coût ETH.
extends AbilityScript

func execute(ctx: EncounterContext) -> void:
	ctx.recover_eth(ctx.user, ctx.dmg(&"normal"))
	ctx.remove_weakness(ctx.user)
	ctx.lock_eth(ctx.user)
	# TODO : prochaine capacité gratuite (coût ETH ignoré) au tour suivant.
