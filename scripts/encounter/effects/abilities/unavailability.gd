## Unavailability — skorpis · Toxic · [ETH loss, redirect next damage received]
## MECHANIC: until the user's next turn, any individual that targets it loses X ETH (the
## targeting trigger is a TODO), and damage aimed at it is redirected to a random other
## individual.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var pool := ctx.others()
	if not pool.is_empty():
		ctx.redirect_next_damage(ctx.user, ctx.random_of(pool))
	# TODO: drain X ETH from any individual that targets the user this turn.
