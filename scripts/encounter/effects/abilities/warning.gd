## Warning — oléni · Variable · [ETH loss, damage reduction/increase or immunity]
## MÉCANIQUE : cible un autre individu, qui perd X ETH ; les dégâts de l'énergie de cette
## capacité qui lui sont infligés sont réduits de moitié jusqu'à son prochain tour.
extends AbilityScript

func execute(ctx: EncounterContext) -> void:
	var t = ctx.primary()
	if t:
		ctx.drain_eth(t, ctx.dmg(&"small"))
		ctx.set_energy_damage_factor(t, ctx.energy(), 0.5)
