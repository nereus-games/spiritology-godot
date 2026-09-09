## Misty Secret — vilgane · Fluid · normal · [change weakness, limit actions]
## MÉCANIQUE : la faiblesse de tout le monde devient Fluide jusqu'à leur prochain tour ;
## aux tours suivants, les rivaux Méditent / utilisent des objets plus souvent (TODO).
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	for f in ctx.all_fighters:
		if not f.is_dissolved():
			ctx.set_weakness(f, GameEnums.Energy.FLUID)
