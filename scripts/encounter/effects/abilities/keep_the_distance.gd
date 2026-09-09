## Keep the Distance — fonéchal · Crystal · normal · [change next TO, limit actions]
## MÉCANIQUE : le user choisit sa position et celle de la cible au prochain tour (l'un
## premier, l'autre dernier). Politique auto : user premier, cible dernière ; la cible ne
## peut utiliser que Méditer au prochain tour.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var t = ctx.primary()
	ctx.move_to_first(ctx.user)
	if t:
		ctx.move_to_last(t)
		ctx.restrict_to(t, ["Meditate"])
