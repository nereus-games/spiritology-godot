## Growth Mindset — kurkab · Random · usage unique · [immunity, recover DEN, recover ETH]
## MÉCANIQUE : requiert que le user ait perdu DEN/ETH récemment. Il regagne X DEN par
## autre individu ; s'il n'a plus d'ETH, il fait le plein ; il ne peut plus perdre de DEN
## jusqu'à son prochain tour.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	if ctx.user.last_damager == null:
		return  # condition non remplie
	ctx.recover_den(ctx.user, ctx.dmg(&"small") * ctx.others().size())
	if ctx.user.eth == 0:
		ctx.recover_eth(ctx.user, ctx.user.max_eth)
	ctx.lock_den(ctx.user)
