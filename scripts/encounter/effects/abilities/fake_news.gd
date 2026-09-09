## Fake News — matzal · Toxic · a lot · [damage reduction/immunity]
## MÉCANIQUE : le user est immunisé aux dégâts Fluide jusqu'au prochain tour ; les dégâts
## Toxiques infligés aux autres individus sont amplifiés (normal/big).
extends AbilityScript

func execute(ctx: EncounterContext) -> void:
	ctx.grant_immunity(ctx.user, [GameEnums.Energy.FLUID])
	for o in ctx.others():
		ctx.set_energy_damage_factor(o, GameEnums.Energy.TOXIC, 1.5)
