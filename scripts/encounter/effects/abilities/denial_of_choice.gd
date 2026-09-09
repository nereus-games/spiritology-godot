## Denial of Choice — kurkab · Toxic · a lot · [change weakness, recover DEN]
## MÉCANIQUE : le user gagne X DEN et perd sa faiblesse ; un rival au hasard ayant une
## faiblesse la perd aussi.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	ctx.recover_den(ctx.user, ctx.dmg(&"normal"))
	ctx.remove_weakness(ctx.user)
	var with_weakness := ctx.opponents().filter(
		func(r): return ctx.weakness_of(r) != GameEnums.Energy.NONE
	)
	if not with_weakness.is_empty():
		ctx.remove_weakness(ctx.random_of(with_weakness))
