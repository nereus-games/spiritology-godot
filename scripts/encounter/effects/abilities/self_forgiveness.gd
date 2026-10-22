## Self-Forgiveness — érdouss · Arcane · single use · [change weakness, recover ETH]
## MECHANIC: the user regains X ETH, loses its weakness, and cannot lose ETH until the next
## turn; if it uses an ability next turn, it pays no ETH cost for it.
##
## The free ability is a next-turn modifier ([method EncounterIndividual.grant_free_next_ability]):
## spent by the first ability used on the next turn, gone if none is.
extends AbilityScript

const NextTurnModifiers := preload("res://scripts/encounter/effects/next_turn_modifiers.gd")


func execute(ctx: EncounterContext) -> void:
	ctx.recover_eth(ctx.user, ctx.dmg(&"normal"))
	ctx.remove_weakness(ctx.user)
	ctx.lock_eth(ctx.user)
	NextTurnModifiers.make_next_ability_free(ctx, ctx.user)
