## Deflection — kalilk · Random · medium · [change weakness, damage reduction/increase]
## MECHANIC: requires that the user has not used the same action twice. The target's weakness
## becomes this ability's energy until its next turn, and weakness-matching damage is doubled for
## everyone this turn (the global doubling is a TODO).
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var t = ctx.primary()
	if t:
		ctx.set_weakness(t, ctx.energy())
	# TODO: double the damage matching each individual's weakness this turn.
