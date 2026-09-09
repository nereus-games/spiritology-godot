## Self-Demand — gaiaz · Variable · normal · [limit actions, recover DEN]
## MÉCANIQUE : le user gagne X DEN ; à son prochain tour, il ne peut utiliser que des
## capacités de la même énergie que celle-ci.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	ctx.recover_den(ctx.user, ctx.dmg(&"normal"))
	ctx.restrict_to(ctx.user, ["énergie = %s" % ctx.energy()])
