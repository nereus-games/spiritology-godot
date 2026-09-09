## Ejection Flurry — forlorn razél · Arcane · a lot · big (15) · [change next TO, damage]
## MÉCANIQUE : le premier rival de l'ordre subit des dégâts et passe dernier au tour
## suivant. Si sa faiblesse est Fluide, les dégâts sont de l'énergie Fluide.
extends AbilityScript

func execute(ctx: EncounterContext) -> void:
	var t = ctx.first_opponent_in_order()
	if t == null:
		return
	if ctx.weakness_of(t) == GameEnums.Energy.FLUID:
		ctx.set_energy(GameEnums.Energy.FLUID)
	ctx.deal_damage(t, ctx.base_damage())
	ctx.move_to_last(t)
