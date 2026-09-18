## Reflux — sadakbia · Fluid · medium · [damage reduction/immunity]
## MECHANIC: until the user's next turn, damage it takes is halved and the other half is sent
## back to the attacker; teammates of the same Spiricosm get this too.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	ctx.scale_all_damage(ctx.user, 0.5)
	ctx.grant_reflect(ctx.user)
	for a in ctx.allies():
		if a.species and ctx.user.species and a.species.spiricosm == ctx.user.species.spiricosm:
			ctx.scale_all_damage(a, 0.5)
			ctx.grant_reflect(a)
