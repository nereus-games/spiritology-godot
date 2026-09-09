## Role Model — fopin · Fluid · [force Talk]
## MÉCANIQUE : les rivaux à faiblesse Fluide sont forcés de Parler (dans leur ordre) ;
## si aucun n'a cette faiblesse, un rival est choisi au hasard.
extends AbilityScript

func execute(ctx: EncounterContext) -> void:
	var targets := ctx.opponents().filter(func(r): return ctx.weakness_of(r) == GameEnums.Energy.FLUID)
	if targets.is_empty():
		var r = ctx.random_opponent()
		if r:
			targets = [r]
	for r in targets:
		ctx.force_talk(r)
