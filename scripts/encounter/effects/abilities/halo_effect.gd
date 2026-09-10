## Halo Effect — oléni · [examine bonus, recover ETH]
## MECHANIC: from turn 2 on, if an individual has the same weakness or took the same action as
## last turn, the user picks it and Examines it, with an info bonus per criterion met; the user
## and the target both recover X ETH. The condition on history is a TODO.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var t = ctx.random_of(ctx.others())
	if t == null:
		return
	ctx.grant_examine_bonus(t, 2)
	ctx.recover_eth(ctx.user, ctx.dmg(&"small"))
	ctx.recover_eth(t, ctx.dmg(&"small"))
