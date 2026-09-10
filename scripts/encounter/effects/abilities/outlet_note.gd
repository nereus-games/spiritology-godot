## Outlet Note — érzélak · Fluid · medium · usage unique · [limit actions, recover DEN]
## MECHANIC: a target on the team recovers all its DEN; the user can only use Meditate next
## turn.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var t = ctx.user  # cible dans l'équipe
	ctx.recover_den(t, t.max_den)
	ctx.restrict_to(ctx.user, ["Meditate"])
