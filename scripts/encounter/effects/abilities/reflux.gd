## Reflux — sadakbia · Fluid · medium · [damage reduction/immunity]
## MÉCANIQUE : jusqu'au prochain tour du user, les dégâts qu'il reçoit sont réduits de
## moitié et l'autre moitié est renvoyée à l'attaquant ; les coéquipiers de même Spiricosme
## en bénéficient aussi. (Approximé au coup suivant via next_damage_factor.)
extends AbilityScript

func execute(ctx: EncounterContext) -> void:
	ctx.modify_damage(ctx.user, 0.5)
	ctx.grant_reflect(ctx.user)
	for a in ctx.allies():
		if a.species and ctx.user.species and a.species.spiricosm == ctx.user.species.spiricosm:
			ctx.modify_damage(a, 0.5)
			ctx.grant_reflect(a)
