## Barrier — razél · Crystal · medium · [damage reduction/immunity, recover ETH]
## MECHANIC: an allied target — the user or its teammate — recovers X ETH; the next Fluid, Toxic
## or Crystal damage that hits it is halved.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var t = ctx.user  # itself by default; the target is on its own side
	ctx.recover_eth(t, ctx.dmg(&"normal"))
	for e in [GameEnums.Energy.FLUID, GameEnums.Energy.TOXIC, GameEnums.Energy.CRYSTAL]:
		ctx.set_energy_damage_factor(t, e, 0.5)
