## Shuffle — sadakbia · Fluid · medium · [change next TO, recover ETH]
## MÉCANIQUE : l'ordre du tour est mélangé ; les individus de faiblesse Chaleur font le
## plein d'ETH. (Échange d'ETH selon les positions : TODO.)
extends AbilityScript

func execute(ctx: EncounterContext) -> void:
	ctx.change_turn_order({"by": "shuffle"})
	for f in ctx.all_fighters:
		if not f.is_dissolved() and ctx.weakness_of(f) == GameEnums.Energy.HEAT:
			ctx.recover_eth(f, f.max_eth)
	# TODO : chaque ETH devient celui de l'individu précédemment à cette position.
