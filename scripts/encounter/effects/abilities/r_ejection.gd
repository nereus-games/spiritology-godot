## (R)ejection — sénskor · Fluid · medium · [change weakness]
## MECHANIC: the user's weakness is hidden from the rivals until its next turn; a coin flip
## either strips its weakness OR restores its default one, undoing a change made this turn; and
## it is immune to Fluid and Toxic damage until its next turn.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	ctx.hide_weakness(ctx.user)
	if ctx.rng.randf() < 0.5:
		ctx.remove_weakness(ctx.user)
	else:
		ctx.reset_weakness(ctx.user)
	ctx.grant_immunity(ctx.user, [GameEnums.Energy.FLUID, GameEnums.Energy.TOXIC])
