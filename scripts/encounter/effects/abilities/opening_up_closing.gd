## Opening up Closing — ravbak · Crystal · small (7) · [damage]
## MECHANIC: damages the user AND the targeted rival; the user flees at the end of the turn.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var t = ctx.primary()
	if t:
		ctx.deal_damage(t, ctx.base_damage())
	ctx.deal_damage(ctx.user, ctx.base_damage())
	ctx.flee(ctx.user)
