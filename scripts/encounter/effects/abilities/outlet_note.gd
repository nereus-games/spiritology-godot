## Outlet Note — érzélak · Fluid · medium · usage unique · [limit actions, recover DEN]
## MÉCANIQUE : une cible de l'équipe récupère tout son DEN ; le user ne peut utiliser que
## Méditer au prochain tour.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var t = ctx.user  # cible dans l'équipe
	ctx.recover_den(t, t.max_den)
	ctx.restrict_to(ctx.user, ["Meditate"])
