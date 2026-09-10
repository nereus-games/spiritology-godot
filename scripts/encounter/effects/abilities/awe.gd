## Awe — érdouss · Heat · [damage]
## MECHANIC: one rival takes damage once per Fiery native present.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var n := ctx.count_natives(GameEnums.Spiricosm.FIERY)
	var t = ctx.primary()
	if t and n > 0:
		ctx.deal_damage(t, ctx.base_damage() * n)
