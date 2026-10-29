## Misty Secret — vilgane · Fluid · normal · [change weakness, limit actions]
## MECHANIC: everyone's weakness becomes Fluid until their next turn; on later turns the rivals
## Meditate and use objects more often: until the user's next turn, every rival is likelier to
## Meditate and to use an object by the balance step. A rival that carries an object plays
## one on itself when the weight wins the draw (see [AutoAgent]); one that carries none has
## nothing to use, and the weight stays recorded.
extends AbilityScript

const ActionWeights := preload("res://scripts/encounter/effects/action_weights.gd")


func execute(ctx: EncounterContext) -> void:
	for f in ctx.all_individuals:
		if not f.is_dissolved():
			ctx.set_weakness(f, GameEnums.Energy.FLUID, 1, f)  # until THEIR next turn
	var bonus := BalanceData.current().action_weight_bonus
	for r in ctx.opponents():
		ActionWeights.weigh(ctx, r, EncounterAction.Kind.MEDITATE, bonus)
		ActionWeights.weigh(ctx, r, EncounterAction.Kind.USE_OBJECT, bonus)
