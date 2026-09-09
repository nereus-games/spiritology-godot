## Gaslighting — zuk · Toxic · normal (10) · [change weakness, damage]
## MÉCANIQUE : le user choisit un coéquipier et un rival : leur faiblesse est cachée aux
## rivaux et changée au hasard. Puis un rival ciblé subit des dégâts pour chaque individu
## dont la faiblesse est cachée (ou absente de l'encyclopédie).
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var mate = ctx.random_of(ctx.allies())
	var foe = ctx.random_opponent()
	for x in [mate, foe]:
		if x:
			ctx.hide_weakness(x)
			ctx.change_weakness(x)
	var t = ctx.primary()
	if t:
		var hidden := (
			ctx
			. all_fighters
			. filter(func(f): return not f.is_dissolved() and f.weakness_hidden)
			. size()
		)
		ctx.deal_damage(t, ctx.base_damage() * maxi(hidden, 1))
