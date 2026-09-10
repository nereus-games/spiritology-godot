## Prohibition — gaiaz · Crystal · normal · normal (10) · [damage, limit actions]
## MECHANIC: the targeted rival has a 50% chance of taking damage, and can only use Meditate next
## turn.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var t = ctx.primary()
	if t == null:
		return
	if ctx.rng.randf() < 0.5:
		ctx.deal_damage(t, ctx.base_damage())
	ctx.restrict_to(t, ["Meditate"])
