## Dark Gambit — yadol · Toxic · [change weakness, limit actions]
## MÉCANIQUE : deux cibles échangent leur faiblesse actuelle ; un coéquipier au hasard ne
## peut utiliser qu'Examiner ou des capacités Toxiques ce tour (= Dark Caroussel).
extends AbilityScript

func execute(ctx: EncounterContext) -> void:
	var pool := ctx.others()
	if pool.size() >= 2:
		ctx.swap_weakness(pool[0], pool[1])
	var mate = ctx.random_of(ctx.allies())
	if mate:
		ctx.restrict_to(mate, ["Examine", "capacités Toxic"])
