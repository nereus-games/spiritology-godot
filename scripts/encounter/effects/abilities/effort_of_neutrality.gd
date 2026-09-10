## Effort of Neutrality — forlorn érzélak · Fluid · normal · single use · [change weakness]
## MECHANIC: the user has no weakness until its next turn; if the teammate's action deals no
## damage, it loses its weakness too. The condition on a future action is approximated by
## applying it to the allies.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	ctx.remove_weakness(ctx.user)
	for a in ctx.allies():
		ctx.remove_weakness(a)  # TODO: only if the ally's action deals no damage
