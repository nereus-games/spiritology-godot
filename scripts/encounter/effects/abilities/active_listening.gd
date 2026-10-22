## Active Listening — gélmi · Arcane · mini · small (7) · [damage reduction, examine bonus]
## MECHANIC: the user takes damage and is immune to ALL non-Arcane damage until its next turn;
## its next Talk yields as much info as an Examine.
##
## "Info" is IFP, the only measure of it there is: that Talk is awarded the Examine row of the
## IFP table. The Talk must still be effective to earn anything, and the bonus is spent by the
## next Talk either way; it lapses if there is none before the user's turn after next.
extends AbilityScript

const NextTurnModifiers := preload("res://scripts/encounter/effects/next_turn_modifiers.gd")


func execute(ctx: EncounterContext) -> void:
	ctx.deal_damage(ctx.user, ctx.base_damage())
	ctx.grant_immunity_except(ctx.user, GameEnums.Energy.ARCANE)
	NextTurnModifiers.make_next_talk_count_as_examine(ctx, ctx.user)
