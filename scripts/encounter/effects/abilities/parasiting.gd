## Parasiting — kurkab · Toxic · a lot · mini (5) · [damage, limit actions]
## MECHANIC: the targeted rival takes damage and is left with only a quarter of its abilities
## for the rest of the encounter — rounded up, drawn at random, and not cumulative.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var t = ctx.primary()
	if t:
		ctx.deal_damage(t, ctx.base_damage())
		ctx.restrict_to(t, ["LOG_RESTRICT_QUARTER_OF_ABILITIES"])
