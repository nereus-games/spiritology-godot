## Dance Battle — jézal · Heat · medium · normal (10) · [damage]
## MECHANIC: the first rival in the turn order takes damage.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var t = ctx.first_opponent_in_order()
	if t:
		ctx.deal_damage(t, ctx.base_damage())
