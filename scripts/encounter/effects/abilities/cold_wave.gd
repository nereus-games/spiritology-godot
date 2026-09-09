## Cold Wave — draka · Heat · normal · mini (5) · [ETH loss, change weakness, damage]
## MÉCANIQUE : le dernier rival ayant fait perdre DEN/ETH au user perd tout son ETH ;
## si sa faiblesse est Chaleur, il subit des dégâts ; le user choisit sa propre faiblesse
## du prochain tour parmi Fluide, Chaleur et sa faiblesse actuelle.
extends AbilityScript

func execute(ctx: EncounterContext) -> void:
	var r = ctx.user.last_damager
	if r and not r.is_dissolved() and r.is_player != ctx.user.is_player:
		ctx.drain_eth(r, r.eth)  # tout son ETH
		if ctx.weakness_of(r) == GameEnums.Energy.HEAT:
			ctx.deal_damage(r, ctx.base_damage())
	var choices := [GameEnums.Energy.FLUID, GameEnums.Energy.HEAT, ctx.weakness_of(ctx.user)]
	ctx.set_weakness(ctx.user, choices[ctx.rng.randi_range(0, choices.size() - 1)])
