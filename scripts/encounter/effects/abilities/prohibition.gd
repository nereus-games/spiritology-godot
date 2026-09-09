## Prohibition — gaiaz · Crystal · normal · normal (10) · [damage, limit actions]
## MÉCANIQUE : le rival ciblé a 50 % de chances de subir des dégâts ; il ne peut utiliser
## que Méditer au prochain tour.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var t = ctx.primary()
	if t == null:
		return
	if ctx.rng.randf() < 0.5:
		ctx.deal_damage(t, ctx.base_damage())
	ctx.restrict_to(t, ["Meditate"])
