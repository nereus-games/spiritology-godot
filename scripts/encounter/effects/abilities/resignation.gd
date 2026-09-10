## Resignation — mastél · Crystal · mini (5) · usage unique · [change weakness, damage, immunity]
## MECHANIC: the user and its allies take damage, lose their weakness, and are immune to Crystal
## damage until their next turn.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	for a in ctx.team():
		ctx.deal_damage(a, ctx.base_damage())
		ctx.remove_weakness(a)
		ctx.grant_immunity(a, [GameEnums.Energy.CRYSTAL])
