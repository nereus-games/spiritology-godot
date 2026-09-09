## Steep in — vérnal · Variable · mini · [change weakness, examine bonus]
## MÉCANIQUE : l'énergie de la capacité = faiblesse actuelle du user. Le user Examine la
## cible, puis sa propre faiblesse devient celle de la cible.
extends AbilityScript

func execute(ctx: EncounterContext) -> void:
	ctx.set_energy(ctx.weakness_of(ctx.user))
	var t = ctx.primary()
	if t:
		ctx.grant_examine_bonus(t, 1)
		ctx.set_weakness(ctx.user, ctx.weakness_of(t))
