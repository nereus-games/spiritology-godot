## Fake News — matzal · Toxic · a lot · [damage reduction/immunity]
## MECHANIC: the user is immune to Fluid damage until the next turn; Toxic damage dealt to the
## other individuals is amplified, from normal to big.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	ctx.grant_immunity(ctx.user, [GameEnums.Energy.FLUID])
	for o in ctx.others():
		ctx.set_energy_damage_factor(o, GameEnums.Energy.TOXIC, 1.5)
