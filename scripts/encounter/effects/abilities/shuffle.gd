## Shuffle — sadakbia · Fluid · medium · [change next TO, recover ETH]
## MECHANIC: the turn order is shuffled; individuals whose weakness is Heat refill their ETH.
## Trading ETH according to the positions is a TODO.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	ctx.change_turn_order({"by": "shuffle"})
	for f in ctx.all_fighters:
		if not f.is_dissolved() and ctx.weakness_of(f) == GameEnums.Energy.HEAT:
			ctx.recover_eth(f, f.max_eth)
	# TODO: each individual's ETH should become that of whoever held its new position before.
