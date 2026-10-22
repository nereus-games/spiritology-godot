## Effort of Neutrality — forlorn érzélak · Fluid · normal · single use · [change weakness]
## MECHANIC: the user has no weakness until its next turn; if the teammate's action deals no
## damage, it loses its weakness too. The teammate keeps its weakness until it has acted, and
## loses it from then until the user's next turn.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	ctx.remove_weakness(ctx.user)
	ctx.watch_reactions()


func react(ctx: EncounterContext, event) -> void:
	if event.is_action() and ctx.is_ally(event.actor) and event.damage_dealt == 0:
		ctx.remove_weakness(event.actor)
