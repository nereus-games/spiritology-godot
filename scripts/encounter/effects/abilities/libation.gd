## Libation — mastél · Fluid · mini · [change weakness, recover DEN]
## MÉCANIQUE : le user et un rival ciblé gagnent X DEN ; leur faiblesse devient Fluide
## (pour ce tour et le suivant — persistance approximée à la ronde).
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	ctx.recover_den(ctx.user, ctx.dmg(&"normal"))
	ctx.set_weakness(ctx.user, GameEnums.Energy.FLUID)
	var t = ctx.primary()
	if t:
		ctx.recover_den(t, ctx.dmg(&"normal"))
		ctx.set_weakness(t, GameEnums.Energy.FLUID)
