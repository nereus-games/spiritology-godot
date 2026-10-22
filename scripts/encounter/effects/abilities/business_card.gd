## Business Card — hibulus · Variable · single use · [force Talk, recover DEN]
## MECHANIC: next turn, rivals sharing the user's origin Talk to it more often (until the user's
## next turn, each is likelier to Talk by the balance step, and its Talk is aimed at the user);
## the user gains X DEN each time a rival Talks to it.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	ctx.recover_den(ctx.user, ctx.dmg(&"small"))
	ctx.watch_reactions()
	for r in ctx.opponents_of_same_origin():
		ctx.weigh_action(
			r,
			EncounterAction.Kind.TALK,
			BalanceData.current().action_weight_bonus,
			EncounterIndividual.UNTIL_NEXT_TURN,
			ctx.user
		)


func react(ctx: EncounterContext, event) -> void:
	if ctx.is_opponent(event.actor) and event.is_action_of(EncounterAction.Kind.TALK):
		if event.targeted(ctx.user):
			ctx.recover_den(ctx.user, ctx.dmg(&"small"))
