## Victimism — granop · Toxic · mini/small · [damage, redirect next damage received]
## MECHANIC: the user takes small damage; any rival that uses Talk before the end of the turn
## takes damage; other damage that would have hit the user is redirected to a random teammate.
## "Before the end of the turn" is until the user's next turn, as for every timed effect.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	ctx.deal_damage(ctx.user, ctx.dmg(&"mini"))
	var mates := ctx.allies()
	if not mates.is_empty():
		ctx.redirect_next_damage(ctx.user, ctx.random_of(mates))
	ctx.watch_reactions()


func react(ctx: EncounterContext, event) -> void:
	if event.is_action_of(EncounterAction.Kind.TALK) and ctx.is_opponent(event.actor):
		ctx.deal_damage(event.actor, ctx.dmg(&"small"))
