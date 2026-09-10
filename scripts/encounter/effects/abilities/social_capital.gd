## Social Capital — oléni · normal · [change weakness, recover ETH]
## MECHANIC: a targeted teammate gains X ETH per individual in the encounter, not counting itself
## or the user; the user may, or may not, pick it a new weakness out of 2.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var allies := ctx.allies()
	var t = ctx.random_of(allies) if not allies.is_empty() else ctx.user
	var n := ctx.others().filter(func(f): return f != t).size()
	ctx.recover_eth(t, ctx.dmg(&"small") * n)
	ctx.change_weakness(t)  # an optional choice of a new weakness
