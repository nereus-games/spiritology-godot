## Oily Residue — sadakbia · Fluid · [damage]
## MECHANIC: one rival takes damage once per Wonderful native.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var n := ctx.count_natives(GameEnums.Spiricosm.WONDERFUL)
	var t = ctx.primary()
	if t and n > 0:
		ctx.deal_damage(t, ctx.base_damage() * n)
