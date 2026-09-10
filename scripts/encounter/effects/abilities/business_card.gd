## Business Card — hibulus · Variable · single use · [force Talk, recover DEN]
## MECHANIC: next turn, rivals sharing the user's origin Talk to it more often (TODO); the user
## gains X DEN each time a rival Talks to it (trigger TODO).
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	ctx.recover_den(ctx.user, ctx.dmg(&"small"))
	# TODO: a talk bonus for same-origin rivals, plus DEN gained when a rival Talks to the user.
