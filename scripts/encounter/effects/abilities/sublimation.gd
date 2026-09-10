## Sublimation — forlorn jézal · Variable · [change next TO]
## MECHANIC: pick your position next turn — first, second, or after all the allies. The automatic
## policy is to go to the front.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	ctx.move_to_first(ctx.user)
