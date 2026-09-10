## Growth Mindset — kurkab · Random · usage unique · [immunity, recover DEN, recover ETH]
## MECHANIC: requires the user to have lost DEN or ETH recently. It regains X DEN per other
## individual; if it is out of ETH, it refills; and it cannot lose DEN until its next turn.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	if ctx.user.last_damager == null:
		return  # condition non remplie
	ctx.recover_den(ctx.user, ctx.dmg(&"small") * ctx.others().size())
	if ctx.user.eth == 0:
		ctx.recover_eth(ctx.user, ctx.user.max_eth)
	ctx.lock_den(ctx.user)
