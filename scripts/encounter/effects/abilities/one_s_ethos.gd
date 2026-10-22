## One's Ethos — akturlin · Crystal · mini · small (7) · [damage]
## MECHANIC: the first rival in the turn order takes damage; rivals sharing the user's origin
## talk 5% more often for the rest of the encounter: 5 points of probability added to their
## chance of Talking, for good. Only rivals standing when it is used are concerned.
extends AbilityScript

const ActionWeights := preload("res://scripts/encounter/effects/action_weights.gd")


func execute(ctx: EncounterContext) -> void:
	var t = ctx.first_opponent_in_order()
	if t:
		ctx.deal_damage(t, ctx.base_damage())
	for r in ActionWeights.same_origin_opponents(ctx):
		ActionWeights.weigh(
			ctx,
			r,
			EncounterAction.Kind.TALK,
			BalanceData.current().ethos_talk_bonus,
			EncounterIndividual.FOR_ENCOUNTER
		)
