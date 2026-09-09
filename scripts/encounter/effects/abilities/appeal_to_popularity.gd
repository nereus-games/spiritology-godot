## Appeal to Popularity — granop · Toxic · a lot · normal (10) · [damage]
## MÉCANIQUE : requiert ≥2 individus partageant la même faiblesse ; un rival subit
## les dégâts autant de fois que le plus grand groupe de même faiblesse.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var n := ctx.largest_same_weakness_group()
	if n < 2:
		return
	var t = ctx.primary()
	if t:
		ctx.deal_damage(t, ctx.base_damage() * n)
