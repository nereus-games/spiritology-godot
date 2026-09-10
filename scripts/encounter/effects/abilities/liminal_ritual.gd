## Liminal Ritual — lulupéa · Variable · single use · [change weakness, recover DEN]
## MECHANIC: usable only while some individual has no weakness. Every individual without one
## regains X DEN and takes this ability's energy as its weakness, until the end of the encounter
## unless another ability changes it.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var no_weakness := ctx.all_individuals.filter(
		func(f): return not f.is_dissolved() and ctx.weakness_of(f) == GameEnums.Energy.NONE
	)
	if no_weakness.is_empty():
		return
	for f in no_weakness:
		ctx.recover_den(f, ctx.dmg(&"normal"))
		ctx.set_weakness(f, ctx.energy())
