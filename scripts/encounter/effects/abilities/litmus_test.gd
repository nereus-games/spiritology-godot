## Litmus Test — granop · [limit actions, recover ETH]
## MÉCANIQUE : les 2 dernières capacités utilisées par la cible lui deviennent inutilisables
## jusqu'à la fin de la rencontre ; le user et la cible gagnent X ETH s'ils sont d'origine différente.
extends AbilityScript

func execute(ctx: EncounterContext) -> void:
	var t = ctx.primary()
	if t == null:
		return
	ctx.restrict_to(t, ["sauf ses 2 dernières capacités"])
	if t.species and ctx.user.species and t.species.spiricosm != ctx.user.species.spiricosm:
		ctx.recover_eth(ctx.user, ctx.dmg(&"small"))
		ctx.recover_eth(t, ctx.dmg(&"small"))
