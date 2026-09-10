## Radiant Secret — forlorn fliritus · Heat · normal · [change weakness, force Talk]
## MECHANIC: the user's and its allies' weakness becomes Heat until their next turn; on later
## turns the targeted rival talks more readily (TODO).
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	for m in ctx.team():
		ctx.set_weakness(m, GameEnums.Energy.HEAT)
