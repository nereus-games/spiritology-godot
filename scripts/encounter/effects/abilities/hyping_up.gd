## Hyping Up — ravbak · Arcane · medium · mini (5) · [damage, force Talk]
## MÉCANIQUE : chaque rival subit des dégâts ; ensuite, 50 % de chances que TOUT LE MONDE
## subisse des dégâts ; aux tours suivants, les rivaux initient Talk plus souvent (TODO).
extends AbilityScript

func execute(ctx: EncounterContext) -> void:
	for r in ctx.opponents():
		ctx.deal_damage(r, ctx.base_damage())
	if ctx.rng.randf() < 0.5:
		for f in ctx.all_fighters:
			if not f.is_dissolved():
				ctx.deal_damage(f, ctx.base_damage())
