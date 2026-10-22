## Hyping Up — ravbak · Arcane · medium · mini (5) · [damage, force Talk]
## MECHANIC: every rival takes damage; then a 50% chance that EVERYONE takes damage; on later
## turns the rivals start Talk more often: every rival is likelier to Talk by the balance step
## until the user's next turn, whether or not the 50% roll hit everyone.
extends AbilityScript

const ActionWeights := preload("res://scripts/encounter/effects/action_weights.gd")


func execute(ctx: EncounterContext) -> void:
	for r in ctx.opponents():
		ctx.deal_damage(r, ctx.base_damage())
		ActionWeights.weigh(
			ctx, r, EncounterAction.Kind.TALK, BalanceData.current().action_weight_bonus
		)
	if ctx.rng.randf() < 0.5:
		for f in ctx.all_individuals:
			if not f.is_dissolved():
				ctx.deal_damage(f, ctx.base_damage())
