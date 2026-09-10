## Sneak Attack — zuk · Heat · medium · normal (10) · [damage]
## MECHANIC: the last rival in the turn order takes damage.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var t = ctx.last_opponent_in_order()
	if t:
		ctx.deal_damage(t, ctx.base_damage())
