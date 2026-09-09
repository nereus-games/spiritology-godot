## Parasiting — kurkab · Toxic · a lot · mini (5) · [damage, limit actions]
## MÉCANIQUE : le rival ciblé subit des dégâts et n'a plus accès qu'à 1/4 de ses capacités
## jusqu'à la fin de la rencontre (arrondi sup., tirées au hasard, non cumulatif).
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var t = ctx.primary()
	if t:
		ctx.deal_damage(t, ctx.base_damage())
		ctx.restrict_to(t, ["1/4 des capacités"])
