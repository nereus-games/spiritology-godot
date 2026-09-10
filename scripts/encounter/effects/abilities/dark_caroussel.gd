## Dark Caroussel — yadol · Arcane · [change weakness, limit actions]
## MECHANIC: two targets swap their current weakness; a random teammate can only use Examine or
## Arcane abilities this turn (the mirror of Dark Gambit).
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var pool := ctx.others()
	if pool.size() >= 2:
		ctx.swap_weakness(pool[0], pool[1])
	var mate = ctx.random_of(ctx.allies())
	if mate:
		ctx.restrict_to(mate, ["Examine", "capacités Arcane"])
