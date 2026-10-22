## Shuffle — sadakbia · Fluid · medium · [change next TO, recover ETH]
## MECHANIC: the turn order is shuffled; individuals whose weakness is Heat refill their ETH.
## Each individual's ETH becomes that of whoever held its new position before.
##
## The doc is silent on several points, settled as follows. The trade is made at once, with the
## ETH everyone has now, although the new order only takes hold at the end of the round. Only
## living individuals take part. The trade comes first and the Heat refill after it, so that
## whoever exposes Heat ends up full whatever it was handed. A later reordering in the same turn
## replaces the shuffle but not the trade.
extends AbilityScript

const OneOffs := preload("res://scripts/encounter/effects/one_off_rules.gd")


func execute(ctx: EncounterContext) -> void:
	OneOffs.shuffle_trading_eth(ctx)
	for f in ctx.all_individuals:
		if not f.is_dissolved() and ctx.weakness_of(f) == GameEnums.Energy.HEAT:
			ctx.recover_eth(f, f.max_eth)
