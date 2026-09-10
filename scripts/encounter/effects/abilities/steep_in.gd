## Steep in — vérnal · Variable · mini · [change weakness, examine bonus]
## MECHANIC: the ability's energy is the user's current weakness. The user Examines the target,
## then its own weakness becomes the target's.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	ctx.set_energy(ctx.weakness_of(ctx.user))
	var t = ctx.primary()
	if t:
		ctx.grant_examine_bonus(t, 1)
		ctx.set_weakness(ctx.user, ctx.weakness_of(t))
