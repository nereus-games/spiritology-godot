## Anomaly — kalilk · small (7) · [damage, limit actions]
## MECHANIC: small damage to one rival; the user loses one of its actions next turn.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var t = ctx.primary()
	if t:
		ctx.deal_damage(t, ctx.dmg(&"small"))
	ctx.limit_actions(ctx.user, 1)
