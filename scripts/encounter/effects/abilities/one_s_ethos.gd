## One's Ethos — akturlin · Crystal · mini · small (7) · [damage]
## MECHANIC: the first rival in the turn order takes damage; rivals sharing the user's origin
## talk 5% more often for the rest of the encounter: 5 points of probability added to their
## chance of Talking, for good. Only rivals standing when it is used are concerned.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var t = ctx.first_opponent_in_order()
	if t:
		ctx.deal_damage(t, ctx.base_damage())
	for r in ctx.opponents_of_same_origin():
		ctx.weigh_action(
			r,
			EncounterAction.Kind.TALK,
			BalanceData.current().ethos_talk_bonus,
			EncounterIndividual.FOR_ENCOUNTER
		)
