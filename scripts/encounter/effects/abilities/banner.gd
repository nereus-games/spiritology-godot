## Banner — zuk · Fluid · medium · [change weakness, damage reduction/immunity]
## MÉCANIQUE : la faiblesse du coéquipier devient celle du user ; les dégâts Chaleur ou
## Cristal reçus par l'équipe sont réduits de moitié jusqu'à la fin du tour.
extends AbilityScript

func execute(ctx: EncounterContext) -> void:
	var w := ctx.weakness_of(ctx.user)
	for a in ctx.allies():
		ctx.set_weakness(a, w)
	for m in ctx.team():
		ctx.set_energy_damage_factor(m, GameEnums.Energy.HEAT, 0.5)
		ctx.set_energy_damage_factor(m, GameEnums.Energy.CRYSTAL, 0.5)
