## Unavailability — skorpis · Toxic · [ETH loss, redirect next damage received]
## MECHANIC: until the user's next turn, any individual that targets it loses X ETH, and damage
## aimed at it is redirected to a random other individual. "Targets it" is an action that names
## the user among its targets; an ability that simply hits everyone does not.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var pool := ctx.others()
	if not pool.is_empty():
		ctx.redirect_next_damage(ctx.user, ctx.random_of(pool))
	ctx.watch_reactions()


func react(ctx: EncounterContext, event) -> void:
	if event.actor != ctx.user and event.targeted(ctx.user):
		ctx.drain_eth(event.actor, EthLossEffect.DEFAULT_AMOUNT)
