## Giving the Floor — korig · Fluid · usage unique · [force Talk, limit actions]
## MÉCANIQUE : jusqu'au prochain tour du user, chacun ne peut utiliser que des capacités
## Fluides ; la prochaine action du rival ciblé est Parler.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	for f in ctx.all_fighters:
		if not f.is_dissolved():
			ctx.restrict_to(f, ["capacités Fluid"])
	var t = ctx.primary()
	if t:
		ctx.force_talk(t)
