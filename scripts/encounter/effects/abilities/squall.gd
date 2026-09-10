## Squall — podargolo · Heat · small (7) · [change weakness, damage]
## MECHANIC: the target takes damage, then its weakness becomes Crystal.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var t = ctx.primary()
	if t:
		ctx.deal_damage(t, ctx.base_damage())
		ctx.set_weakness(t, GameEnums.Energy.CRYSTAL)
