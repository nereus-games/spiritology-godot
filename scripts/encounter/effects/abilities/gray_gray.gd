## Gray-Gray — basipik · Arcane · usage unique · [damage reduction/immunity]
## MECHANIC: the rivals can no longer see the user's DEN or weakness (a UI effect) for the rest
## of the encounter; the user is immune to Arcane damage until its next turn.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	ctx.hide_weakness(ctx.user)
	ctx.request_ui(&"hide_user_den_weakness", {"fighter": ctx.user.species_id()})
	ctx.grant_immunity(ctx.user, [GameEnums.Energy.ARCANE])
