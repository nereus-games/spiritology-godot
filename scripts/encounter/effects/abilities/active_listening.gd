## Active Listening — gélmi · Arcane · mini · small (7) · [damage reduction, examine bonus]
## MÉCANIQUE : le user subit des dégâts ; il est immunisé à TOUS les dégâts non-Arcane
## jusqu'à son prochain tour ; son prochain Talk rapporte autant d'info qu'Examiner (TODO).
extends AbilityScript

func execute(ctx: EncounterContext) -> void:
	ctx.deal_damage(ctx.user, ctx.base_damage())
	ctx.grant_immunity_except(ctx.user, GameEnums.Energy.ARCANE)
