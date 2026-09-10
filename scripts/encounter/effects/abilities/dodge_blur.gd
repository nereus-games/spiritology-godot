## Dodge Blur — podargolo · Toxic · medium · mini/small · [damage, damage reduction]
## MECHANIC: the user takes small damage; any rival that uses Talk before the end of the turn
## takes damage (TODO); all other damage dealt before the end of the turn is halved.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	ctx.deal_damage(ctx.user, ctx.dmg(&"mini"))
	ctx.modify_damage(ctx.user, 0.5)
	# TODO: every rival that uses Talk this turn takes small; mitigation for the whole turn.
