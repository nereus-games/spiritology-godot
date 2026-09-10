## Cold Wave — draka · Heat · normal · mini (5) · [ETH loss, change weakness, damage]
## MECHANIC: the last rival to have cost the user DEN or ETH loses all its ETH, and takes damage
## if its weakness is Heat; the user picks its own next-turn weakness from Fluid, Heat and its
## current one.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var r = ctx.user.last_damager
	if r and not r.is_dissolved() and r.is_player != ctx.user.is_player:
		ctx.drain_eth(r, r.eth)  # all of its ETH
		if ctx.weakness_of(r) == GameEnums.Energy.HEAT:
			ctx.deal_damage(r, ctx.base_damage())
	var choices := [GameEnums.Energy.FLUID, GameEnums.Energy.HEAT, ctx.weakness_of(ctx.user)]
	ctx.set_weakness(ctx.user, choices[ctx.rng.randi_range(0, choices.size() - 1)])
