## Altruism — érdouss · Fluid · mini · [recover DEN]
## MÉCANIQUE : détruit un objet de l'inventaire (choisi par le user), puis la cible gagne
## X DEN. (Destruction d'objet via l'inventaire de la session : TODO.)
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var t = ctx.primary()
	if t == null:
		t = ctx.user
	ctx.recover_den(t, ctx.dmg(&"normal"))
	# TODO : détruire un objet de GameSession.inventory en contrepartie du soin.
