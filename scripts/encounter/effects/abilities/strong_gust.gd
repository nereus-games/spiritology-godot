## Strong Gust — forlorn podargolo · Heat · normal (10) · [change next TO, damage]
## MECHANIC: the target takes damage, if it is a rival, and moves last next turn.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var t = ctx.primary()
	if t == null:
		return
	if t.is_player != ctx.user.is_player:
		ctx.deal_damage(t, ctx.base_damage())
	ctx.move_to_last(t)
