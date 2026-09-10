## Numbing Secret — mastél · mini (5) · [damage, limit actions]
## MECHANIC: the targeted rival takes damage and can no longer use Talk or any Heat ability for
## the rest of the encounter, or until it Meditates.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var t = ctx.primary()
	if t:
		ctx.deal_damage(t, ctx.base_damage())
		ctx.restrict_to(t, ["LOG_RESTRICT_EXCEPT_TALK", "LOG_RESTRICT_EXCEPT_ABILITIES_HEAT"])
