## Business Card — hibulus · Variable · single use · [force Talk, recover DEN]
## MECHANIC: next turn, rivals sharing the user's origin Talk to it more often (TODO); the user
## gains X DEN each time a rival Talks to it.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	ctx.recover_den(ctx.user, ctx.dmg(&"small"))
	ctx.watch_reactions()
	# TODO: a talk bonus for same-origin rivals; needs rivals to choose their action by weight.


func react(ctx: EncounterContext, event) -> void:
	if ctx.is_opponent(event.actor) and event.is_action_of(EncounterAction.Kind.TALK):
		if event.targeted(ctx.user):
			ctx.recover_den(ctx.user, ctx.dmg(&"small"))
