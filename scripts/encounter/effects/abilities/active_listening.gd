## Active Listening — gélmi · Arcane · mini · small (7) · [damage reduction, examine bonus]
## MECHANIC: the user takes damage and is immune to ALL non-Arcane damage until its next turn;
## its next Talk yields as much info as an Examine (TODO).
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	ctx.deal_damage(ctx.user, ctx.base_damage())
	ctx.grant_immunity_except(ctx.user, GameEnums.Energy.ARCANE)
