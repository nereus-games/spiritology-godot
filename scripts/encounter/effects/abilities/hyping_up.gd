## Hyping Up — ravbak · Arcane · medium · mini (5) · [damage, force Talk]
## MECHANIC: every rival takes damage; then a 50% chance that EVERYONE takes damage; on later
## turns the rivals start Talk more often (TODO).
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	for r in ctx.opponents():
		ctx.deal_damage(r, ctx.base_damage())
	if ctx.rng.randf() < 0.5:
		for f in ctx.all_fighters:
			if not f.is_dissolved():
				ctx.deal_damage(f, ctx.base_damage())
