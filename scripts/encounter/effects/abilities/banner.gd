## Banner — zuk · Fluid · medium · [change weakness, damage reduction/immunity]
## MECHANIC: the teammate's weakness becomes the user's; Heat and Crystal damage taken by the
## team is halved until the end of the turn.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var w := ctx.weakness_of(ctx.user)
	for a in ctx.allies():
		ctx.set_weakness(a, w)
	for m in ctx.team():
		ctx.set_energy_damage_factor(m, GameEnums.Energy.HEAT, 0.5)
		ctx.set_energy_damage_factor(m, GameEnums.Energy.CRYSTAL, 0.5)
