## Numbing Secret — mastél · mini (5) · [damage, limit actions]
## MÉCANIQUE : le rival ciblé subit des dégâts et ne peut plus utiliser Talk ni aucune
## capacité Chaleur jusqu'à la fin de la rencontre (ou jusqu'à ce qu'il Médite).
extends AbilityScript

func execute(ctx: EncounterContext) -> void:
	var t = ctx.primary()
	if t:
		ctx.deal_damage(t, ctx.base_damage())
		ctx.restrict_to(t, ["sauf Talk", "sauf capacités Heat"])
