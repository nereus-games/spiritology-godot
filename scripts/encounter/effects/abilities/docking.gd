## Docking — draka · Fluid · medium · normal/small · [change weakness, damage]
## MECHANIC: targets a rival immediately before or after the user in the turn order, and does
## nothing otherwise. Normal damage if they share a weakness, small otherwise; the target's
## weakness becomes the user's; then small damage again, so twice in all.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var order: Array = ctx.timeline.order if ctx.timeline else ctx.all_fighters
	var i := order.find(ctx.user)
	var t = null
	for j in [i - 1, i + 1]:
		if (
			j >= 0
			and j < order.size()
			and order[j].is_player != ctx.user.is_player
			and not order[j].is_dissolved()
		):
			t = order[j]
			break
	if t == null:
		return
	var shares := ctx.weakness_of(t) == ctx.weakness_of(ctx.user)
	ctx.deal_damage(t, ctx.dmg(&"normal") if shares else ctx.dmg(&"small"))
	ctx.set_weakness(t, ctx.weakness_of(ctx.user))
	ctx.deal_damage(t, ctx.dmg(&"small"))
