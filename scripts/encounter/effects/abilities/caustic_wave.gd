## Caustic Wave — spodra · Toxic · mini · mini (5) · [change weakness, damage]
## MÉCANIQUE : tous les rivaux subissent des dégâts ; chaque rival touché a X %
## de chances de voir sa faiblesse devenir Toxique.
extends AbilityScript

const WEAKNESS_CHANCE := 0.5  ## X % (à équilibrer)

func execute(ctx: EncounterContext) -> void:
	for r in ctx.opponents():
		ctx.deal_damage(r, ctx.base_damage())
		if ctx.rng.randf() < WEAKNESS_CHANCE:
			ctx.set_weakness(r, GameEnums.Energy.TOXIC)
