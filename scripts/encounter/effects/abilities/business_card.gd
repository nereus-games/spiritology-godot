## Business Card — hibulus · Variable · single use · [force Talk, recover DEN]
## MECHANIC: next turn, rivals sharing the user's origin Talk to it more often (until the user's
## next turn, each is likelier to Talk by the balance step, and its Talk is aimed at the user);
## the user gains X DEN each time a rival Talks to it.
extends AbilityScript

const ActionWeights := preload("res://scripts/encounter/effects/action_weights.gd")


func execute(ctx: EncounterContext) -> void:
	ctx.recover_den(ctx.user, ctx.dmg(&"small"))
	ctx.watch_reactions()
	for r in ActionWeights.same_origin_opponents(ctx):
		ActionWeights.weigh(
			ctx,
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
