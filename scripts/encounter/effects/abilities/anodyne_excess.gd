## Anodyne Excess — vérnal · Variable · usage unique · [change weakness]
## MÉCANIQUE : chaque tour, les autres individus ont une forte chance d'adopter l'énergie de
## cette capacité comme faiblesse ; les indicateurs ETH/DEN des rivaux deviennent invisibles
## (UI). Effets jusqu'à la fin de la rencontre ou jusqu'à ce que le user Médite.
extends AbilityScript

const WEAKNESS_CHANCE := 0.7


func execute(ctx: EncounterContext) -> void:
	ctx.request_ui(&"hide_rival_stats", {"until": "encounter_end", "cancel_on": "meditate"})
	for o in ctx.others():
		if ctx.rng.randf() < WEAKNESS_CHANCE:
			ctx.set_weakness(o, ctx.energy())
