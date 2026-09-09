## Critical Mass — gélmi · a lot · [damage, recover DEN]
## MÉCANIQUE : chaque membre de l'équipe gagne X DEN, puis si tout le DEN de l'équipe est au
## maximum, inflige des dégâts à chaque rival.
extends AbilityScript

func execute(ctx: EncounterContext) -> void:
	for m in ctx.team():
		ctx.recover_den(m, ctx.dmg(&"small"))
	var full := ctx.team().all(func(f): return f.den >= f.max_den)
	if full:
		for r in ctx.opponents():
			ctx.deal_damage(r, ctx.base_damage())
