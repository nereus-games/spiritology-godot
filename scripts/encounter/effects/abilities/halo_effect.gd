## Halo Effect — oléni · [examine bonus, recover ETH]
## MÉCANIQUE : (à partir du 2e tour, si un individu a la même faiblesse ou a fait la même
## action qu'au tour précédent) le user le choisit, l'Examine (bonus d'info par critère
## rempli) ; le user et la cible récupèrent X ETH. (Condition historique : TODO.)
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var t = ctx.random_of(ctx.others())
	if t == null:
		return
	ctx.grant_examine_bonus(t, 2)
	ctx.recover_eth(ctx.user, ctx.dmg(&"small"))
	ctx.recover_eth(t, ctx.dmg(&"small"))
