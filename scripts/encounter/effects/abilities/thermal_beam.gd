## Thermal Beam — razél · Heat · normal · normal (10) · [damage]
## MÉCANIQUE : 3 cibles rivales (répétitions possibles) subissent des dégâts ;
## réduits si le user est bas en vie : small entre 50–75 % DEN, mini sous 50 %.
extends AbilityScript

func execute(ctx: EncounterContext) -> void:
	var ratio := float(ctx.user.den) / maxf(ctx.user.max_den, 1)
	var tier := &"normal"
	if ratio < 0.5:
		tier = &"mini"
	elif ratio < 0.75:
		tier = &"small"
	for t in ctx.random_opponents(3, true):
		ctx.deal_damage(t, ctx.dmg(tier))
