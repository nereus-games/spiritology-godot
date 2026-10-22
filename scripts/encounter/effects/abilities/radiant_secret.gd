## Radiant Secret — forlorn fliritus · Heat · normal · [change weakness, force Talk]
## MECHANIC: the user's and its allies' weakness becomes Heat until their next turn; on later
## turns the targeted rival talks more readily: until the user's next turn, each targeted rival
## is likelier to Talk by the balance step (the doc gives no figure).
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	for m in ctx.team():
		ctx.set_weakness(m, GameEnums.Energy.HEAT, 1, m)  # until THEIR next turn
	for t in ctx.targets:
		if ctx.is_opponent(t):
			ctx.weigh_action(
				t, EncounterAction.Kind.TALK, BalanceData.current().action_weight_bonus
			)
