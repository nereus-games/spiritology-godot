## Victimism — granop · Toxic · mini/small · [damage, redirect next damage received]
## MECHANIC: the user takes small damage; any rival that uses Talk before the end of the turn
## takes damage (the Talk trigger is a TODO); other damage that would have hit the user is
## redirected to a random teammate.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	ctx.deal_damage(ctx.user, ctx.dmg(&"mini"))
	var mates := ctx.allies()
	if not mates.is_empty():
		ctx.redirect_next_damage(ctx.user, ctx.random_of(mates))
	# TODO: punish every rival that uses Talk this turn (ctx.dmg("small")).
