## Self-Disclosure — vilgane · [recover ETH]
## MECHANIC: a pool of ETH, proportional to how many abilities the user has used during the
## encounter, is shared equally between all individuals.
##
## The abilities used are counted in the encounter history, this one included. The pool is one
## "small" tier of ETH per ability used — a placeholder, the doc gives no figure — and each living
## individual, the user among them, gets an equal share of it, rounded down.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var living: Array = []
	for f in ctx.all_individuals:
		if not f.is_dissolved():
			living.append(f)
	if living.is_empty():
		return
	var pool: int = ctx.dmg(&"small") * (ctx.history.abilities_used(ctx.user) + 1)
	var share := floori(float(pool) / living.size())
	for f in living:
		ctx.recover_eth(f, share)
