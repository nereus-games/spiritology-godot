## Resignation — mastél · Crystal · mini (5) · usage unique · [change weakness, damage, immunity]
## MÉCANIQUE : le user et ses alliés subissent des dégâts, perdent leur faiblesse et sont
## immunisés aux dégâts Cristal jusqu'à leur prochain tour.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	for a in ctx.team():
		ctx.deal_damage(a, ctx.base_damage())
		ctx.remove_weakness(a)
		ctx.grant_immunity(a, [GameEnums.Energy.CRYSTAL])
