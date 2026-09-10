## Mushify — malcouli · Heat · a lot · normal (10) · [change weakness, damage]
## MECHANIC: the target takes damage, then its weakness becomes Fluid.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var t = ctx.primary()
	if t:
		ctx.deal_damage(t, ctx.base_damage())
		ctx.set_weakness(t, GameEnums.Energy.FLUID)
