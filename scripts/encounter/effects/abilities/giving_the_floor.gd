## Giving the Floor — korig · Fluid · usage unique · [force Talk, limit actions]
## MECHANIC: until the user's next turn, everyone can only use Fluid abilities; the targeted
## rival's next action is Talk.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	for f in ctx.all_fighters:
		if not f.is_dissolved():
			ctx.restrict_to(f, ["capacités Fluid"])
	var t = ctx.primary()
	if t:
		ctx.force_talk(t)
