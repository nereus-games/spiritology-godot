## Commendation — lulupéa · [damage reduction/increase, recover ETH]
## MÉCANIQUE : une cible (différente du user) gagne beaucoup d'ETH, mais chaque dégât Arcane
## ou Cristal qu'elle reçoit jusqu'à son prochain tour a 50 % de chances d'être doublé.
## (Approximé par un facteur moyen ×1.25.)
extends AbilityScript

func execute(ctx: EncounterContext) -> void:
	var t = ctx.random_of(ctx.others())
	if t == null:
		return
	ctx.recover_eth(t, ctx.dmg(&"normal"))
	ctx.set_energy_damage_factor(t, GameEnums.Energy.ARCANE, 1.25)
	ctx.set_energy_damage_factor(t, GameEnums.Energy.CRYSTAL, 1.25)
