## Squall — podargolo · Heat · small (7) · [change weakness, damage]
## MÉCANIQUE : la cible subit des dégâts, puis sa faiblesse devient Cristal.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var t = ctx.primary()
	if t:
		ctx.deal_damage(t, ctx.base_damage())
		ctx.set_weakness(t, GameEnums.Energy.CRYSTAL)
