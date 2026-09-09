## Awe — érdouss · Heat · [damage]
## MÉCANIQUE : un rival subit des dégâts pour chaque natif d'Ardent (Fiery) présent.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var n := ctx.count_natives(GameEnums.Spiricosm.FIERY)
	var t = ctx.primary()
	if t and n > 0:
		ctx.deal_damage(t, ctx.base_damage() * n)
