## Gaslighting — zuk · Toxic · normal (10) · [change weakness, damage]
## MECHANIC: the user picks one teammate and one rival, whose weakness is hidden from the rivals
## and changed at random. Then a targeted rival takes damage once per individual whose weakness
## is hidden, or missing from the encyclopaedia.
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
