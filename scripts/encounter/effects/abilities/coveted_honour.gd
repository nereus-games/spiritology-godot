## Coveted Honour — fopin · Arcane · mini (5) · [damage, recover DEN]
## MECHANIC: whichever of the user and its allies is last in the turn order gains X DEN; a random
## rival takes damage.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var ally = ctx.last_of_team_in_order()
	if ally:
		ctx.recover_den(ally, ctx.dmg(&"normal"))
	var t = ctx.random_opponent()
	if t:
		ctx.deal_damage(t, ctx.base_damage())
