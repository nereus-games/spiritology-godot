## Misty Secret — vilgane · Fluid · normal · [change weakness, limit actions]
## MECHANIC: everyone's weakness becomes Fluid until their next turn; on later turns the rivals
## Meditate and use objects more often (TODO).
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	for f in ctx.all_individuals:
		if not f.is_dissolved():
			ctx.set_weakness(f, GameEnums.Energy.FLUID)
