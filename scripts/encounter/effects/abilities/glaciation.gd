## Glaciation — yilir · Crystal · small (7) · [damage, damage reduction/immunity]
## MECHANIC: one rival takes damage. If the target is on the team, it cancels all damage — and
## toxic effects — for the current turn.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var t = ctx.primary()
	if t == null:
		return
	if t.is_player == ctx.user.is_player:
		ctx.grant_full_immunity(t)
	else:
		ctx.deal_damage(t, ctx.base_damage())
