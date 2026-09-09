## Mushify — malcouli · Heat · a lot · normal (10) · [change weakness, damage]
## MÉCANIQUE : la cible subit des dégâts, puis sa faiblesse devient Fluide.
extends AbilityScript

func execute(ctx: EncounterContext) -> void:
	var t = ctx.primary()
	if t:
		ctx.deal_damage(t, ctx.base_damage())
		ctx.set_weakness(t, GameEnums.Energy.FLUID)
