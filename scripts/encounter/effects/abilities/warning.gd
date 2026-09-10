## Warning — oléni · Variable · [ETH loss, damage reduction/increase or immunity]
## MECHANIC: targets another individual, which loses X ETH; damage of this ability's energy dealt
## to it is halved until its next turn.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var t = ctx.primary()
	if t:
		ctx.drain_eth(t, ctx.dmg(&"small"))
		ctx.set_energy_damage_factor(t, ctx.energy(), 0.5)
