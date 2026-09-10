## Self-Demand — gaiaz · Variable · normal · [limit actions, recover DEN]
## MECHANIC: the user gains X DEN; on its next turn it can only use abilities of this ability's
## energy.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	ctx.recover_den(ctx.user, ctx.dmg(&"normal"))
	ctx.restrict_to(ctx.user, [ctx.abilities_of_key(ctx.energy())])
