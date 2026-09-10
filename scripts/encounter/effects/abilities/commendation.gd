## Commendation — lulupéa · [damage reduction/increase, recover ETH]
## MECHANIC: a target other than the user gains a lot of ETH, but every Arcane or Crystal hit it
## takes until its next turn has a 50% chance of being doubled. Approximated by an average factor
## of x1.25.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var t = ctx.random_of(ctx.others())
	if t == null:
		return
	ctx.recover_eth(t, ctx.dmg(&"normal"))
	ctx.set_energy_damage_factor(t, GameEnums.Energy.ARCANE, 1.25)
	ctx.set_energy_damage_factor(t, GameEnums.Energy.CRYSTAL, 1.25)
