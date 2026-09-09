## Call of the Void — vérnal · Arcane · a lot · big (15) · [change weakness, damage]
## MÉCANIQUE : tous les rivaux SANS faiblesse subissent des dégâts ;
## la faiblesse du user et de ses alliés devient Arcane.
extends AbilityScript

func execute(ctx: EncounterContext) -> void:
	for r in ctx.opponents():
		if ctx.weakness_of(r) == GameEnums.Energy.NONE:
			ctx.deal_damage(r, ctx.base_damage())
	for a in ctx.team():
		ctx.set_weakness(a, GameEnums.Energy.ARCANE)
