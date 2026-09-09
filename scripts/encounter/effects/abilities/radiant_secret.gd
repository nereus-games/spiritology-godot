## Radiant Secret — forlorn fliritus · Heat · normal · [change weakness, force Talk]
## MÉCANIQUE : la faiblesse du user et de ses alliés devient Chaleur jusqu'à leur prochain
## tour ; aux tours suivants, le rival ciblé dialogue plus volontiers (TODO).
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	for m in ctx.team():
		ctx.set_weakness(m, GameEnums.Energy.HEAT)
