## Placebo Sprinkle — matzal · Fluid · mini · mini (5) · [change weakness, damage, recover actions]
## MECHANIC: everyone takes damage; next turn, random individuals lose their weakness and get
## all their actions and abilities back.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	for f in ctx.all_individuals:
		if not f.is_dissolved():
			ctx.deal_damage(f, ctx.base_damage())
	for f in ctx.others():
		if ctx.rng.randf() < 0.5:
			ctx.remove_weakness(f)
			ctx.recover_actions(f, 99)
