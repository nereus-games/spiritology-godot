## Unavailability — skorpis · Toxic · [ETH loss, redirect next damage received]
## MÉCANIQUE : jusqu'au prochain tour du user, tout individu le ciblant perd X ETH
## (TODO : déclencheur de ciblage) et les dégâts qui le touchent sont redirigés vers un
## autre individu au hasard.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var pool := ctx.others()
	if not pool.is_empty():
		ctx.redirect_next_damage(ctx.user, ctx.random_of(pool))
	# TODO : drainer X ETH à tout individu ciblant le user ce tour.
