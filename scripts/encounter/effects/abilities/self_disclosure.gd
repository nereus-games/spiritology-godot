## Self-Disclosure — vilgane · [recover ETH]
## MECHANIC: a pool of ETH, proportional to how many abilities the user has used during the
## encounter, is shared equally between all individuals. Counting the abilities used is a TODO,
## so for now each individual gets a fixed amount.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	for f in ctx.all_fighters:
		if not f.is_dissolved():
			ctx.recover_eth(f, ctx.dmg(&"small"))
