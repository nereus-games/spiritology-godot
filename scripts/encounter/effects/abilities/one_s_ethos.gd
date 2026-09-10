## One's Ethos — akturlin · Crystal · mini · small (7) · [damage]
## MECHANIC: the first rival in the turn order takes damage; rivals sharing the user's origin
## talk 5% more often for the rest of the encounter (TODO).
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var t = ctx.first_opponent_in_order()
	if t:
		ctx.deal_damage(t, ctx.base_damage())
