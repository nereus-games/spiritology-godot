## Altruism — érdouss · Fluid · mini · [recover DEN]
## MECHANIC: destroys an object from the inventory, picked by the user, then the target gains
## X DEN. Destroying the object through the session inventory is a TODO.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var t = ctx.primary()
	if t == null:
		t = ctx.user
	ctx.recover_den(t, ctx.dmg(&"normal"))
	# TODO: destroy an object from GameSession.inventory to pay for the healing.
