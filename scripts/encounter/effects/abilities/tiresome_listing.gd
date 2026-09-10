## Tiresome Listing — érzélak · Toxic · normal · small (7) · [damage]
## MECHANIC: the target takes damage once per band of abilities recorded in the encyclopaedia;
## the user has a 1-in-3 chance of taking half of it. How many abilities are known is
## approximated by the number of completed species.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var known := maxi(ctx.completed_species.size(), 1)
	var t = ctx.primary()
	if t:
		ctx.deal_damage(t, ctx.base_damage() * known)
	if ctx.rng.randf() < 1.0 / 3.0:
		ctx.deal_damage(ctx.user, ctx.base_damage() * known / 2)
