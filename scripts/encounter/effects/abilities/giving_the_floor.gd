## Giving the Floor — korig · Fluid · single use · [force Talk, limit actions]
## MECHANIC: until the user's next turn, everyone can only use Fluid abilities; the targeted
## rival's next action is Talk.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	for f in ctx.all_individuals:
		if not f.is_dissolved():
			ctx.restrict_to(f, [ctx.abilities_of_key(GameEnums.Energy.FLUID)])
	var t = ctx.primary()
	if t:
		ctx.force_talk(t)
