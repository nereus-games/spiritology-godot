## Sad Song — korig · Arcane · small (7) · [change weakness, damage]
## MECHANIC: the target takes damage, then its weakness becomes Heat (the mirror of Worrisome
## Song).
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var t = ctx.primary()
	if t:
		ctx.deal_damage(t, ctx.base_damage())
		ctx.set_weakness(t, GameEnums.Energy.HEAT)
