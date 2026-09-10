## Anodyne Excess — vérnal · Variable · single use · [change weakness]
## MECHANIC: every turn, the other individuals have a high chance of taking this ability's
## energy as their weakness, and the rivals' ETH/DEN readouts go invisible (a UI effect). Both
## last until the end of the encounter, or until the user Meditates.
extends AbilityScript

const WEAKNESS_CHANCE := 0.7


func execute(ctx: EncounterContext) -> void:
	ctx.request_ui(&"hide_rival_stats", {"until": "encounter_end", "cancel_on": "meditate"})
	for o in ctx.others():
		if ctx.rng.randf() < WEAKNESS_CHANCE:
			ctx.set_weakness(o, ctx.energy())
