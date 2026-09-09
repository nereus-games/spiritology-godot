## Placebo Sprinkle — matzal · Fluid · mini · mini (5) · [change weakness, damage, recover actions]
## MÉCANIQUE : tout le monde subit des dégâts ; au tour suivant, des individus au hasard
## perdent leur faiblesse et retrouvent toutes leurs actions/capacités disponibles.
extends AbilityScript

func execute(ctx: EncounterContext) -> void:
	for f in ctx.all_fighters:
		if not f.is_dissolved():
			ctx.deal_damage(f, ctx.base_damage())
	for f in ctx.others():
		if ctx.rng.randf() < 0.5:
			ctx.remove_weakness(f)
			ctx.recover_actions(f, 99)
