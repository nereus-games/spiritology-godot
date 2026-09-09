## Hardening — firulis · Crystal · normal · [damage reduction/immunity]
## MÉCANIQUE : une cible de l'équipe devient immunisée aux dégâts Cristal et voit tous ses
## dégâts réduits de moitié jusqu'à son prochain tour. (Malus d'info via Talk : TODO.)
extends AbilityScript

func execute(ctx: EncounterContext) -> void:
	var t = ctx.user
	ctx.grant_immunity(t, [GameEnums.Energy.CRYSTAL])
	ctx.modify_damage(t, 0.5)
