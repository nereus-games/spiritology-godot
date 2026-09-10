## Appeal to Popularity — granop · Toxic · a lot · normal (10) · [damage]
## MECHANIC: requires at least 2 individuals sharing a weakness; one rival takes the damage as
## many times as the largest same-weakness group is big.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var n := ctx.largest_same_weakness_group()
	if n < 2:
		return
	var t = ctx.primary()
	if t:
		ctx.deal_damage(t, ctx.base_damage() * n)
