## Thermal Beam — razél · Heat · normal · normal (10) · [damage]
## MECHANIC: 3 rival targets take damage, repeats allowed, reduced when the user is low: small
## between 50 and 75% DEN, mini below 50%.
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
