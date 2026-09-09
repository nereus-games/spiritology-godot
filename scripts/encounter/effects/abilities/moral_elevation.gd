## Moral Elevation — sopiark · normal (10) · usage unique · [change weakness, immunity, recover ETH]
## MÉCANIQUE : (utilisable seulement si un individu a aidé un rival à récupérer ETH/DEN ou lui
## a donné un objet récemment) le user refait le plein d'ETH, perd sa faiblesse, et personne
## ne peut changer sa faiblesse jusqu'à son prochain tour. (Condition d'entraide : TODO.)
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	ctx.recover_eth(ctx.user, ctx.user.max_eth)
	ctx.remove_weakness(ctx.user)
	ctx.lock_weakness(ctx.user)
