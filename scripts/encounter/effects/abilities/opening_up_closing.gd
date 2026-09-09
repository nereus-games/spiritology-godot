## Opening up Closing — ravbak · Crystal · small (7) · [damage]
## MÉCANIQUE : inflige des dégâts au user ET au rival ciblé ; le user fuit en fin de tour.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var t = ctx.primary()
	if t:
		ctx.deal_damage(t, ctx.base_damage())
	ctx.deal_damage(ctx.user, ctx.base_damage())
	ctx.flee(ctx.user)
