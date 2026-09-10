## Overthrow — sopiark · Heat · a lot · small (7) · [damage, limit actions, recover DEN]
## MECHANIC: the targeted rival takes damage; if it is devitalised, the user gains X DEN; the
## target loses an action next turn.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var t = ctx.primary()
	if t == null:
		return
	ctx.deal_damage(t, ctx.base_damage())
	if t.is_dissolved():
		ctx.recover_den(ctx.user, ctx.dmg(&"normal"))
	ctx.limit_actions(t, 1)
