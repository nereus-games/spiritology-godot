## Victimism — granop · Toxic · mini/small · [damage, redirect next damage received]
## MÉCANIQUE : le user subit de petits dégâts ; tout rival utilisant Talk avant la fin du
## tour subit des dégâts (TODO : déclencheur Talk) ; les autres dégâts qui devaient le
## toucher sont redirigés vers un coéquipier au hasard.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	ctx.deal_damage(ctx.user, ctx.dmg(&"mini"))
	var mates := ctx.allies()
	if not mates.is_empty():
		ctx.redirect_next_damage(ctx.user, ctx.random_of(mates))
	# TODO : punir tout rival utilisant Talk ce tour (ctx.dmg("small")).
