## Critical Mass — gélmi · a lot · [damage, recover DEN]
## MECHANIC: every team member gains X DEN, and then, if the whole team is at full DEN, every
## rival takes damage.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	for m in ctx.team():
		ctx.recover_den(m, ctx.dmg(&"small"))
	var full := ctx.team().all(func(f): return f.den >= f.max_den)
	if full:
		for r in ctx.opponents():
			ctx.deal_damage(r, ctx.base_damage())
