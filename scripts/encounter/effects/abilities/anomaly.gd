## Anomaly — kalilk · small (7) · [damage, limit actions]
## MÉCANIQUE : petits dégâts à un rival ; le user perd une de ses actions au tour suivant.
extends AbilityScript

func execute(ctx: EncounterContext) -> void:
	var t = ctx.primary()
	if t:
		ctx.deal_damage(t, ctx.dmg(&"small"))
	ctx.limit_actions(ctx.user, 1)
