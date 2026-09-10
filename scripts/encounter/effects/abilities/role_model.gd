## Role Model — fopin · Fluid · [force Talk]
## MECHANIC: rivals whose weakness is Fluid are forced to Talk, in turn order; if none has that
## weakness, one rival is picked at random.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var targets := ctx.opponents().filter(
		func(r): return ctx.weakness_of(r) == GameEnums.Energy.FLUID
	)
	if targets.is_empty():
		var r = ctx.random_opponent()
		if r:
			targets = [r]
	for r in targets:
		ctx.force_talk(r)
