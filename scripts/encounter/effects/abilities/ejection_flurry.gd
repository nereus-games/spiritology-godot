## Ejection Flurry — forlorn razél · Arcane · a lot · big (15) · [change next TO, damage]
## MECHANIC: the first rival in the order takes damage and moves last next turn. If its weakness
## is Fluid, the damage is Fluid energy.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var t = ctx.first_opponent_in_order()
	if t == null:
		return
	if ctx.weakness_of(t) == GameEnums.Energy.FLUID:
		ctx.set_energy(GameEnums.Energy.FLUID)
	ctx.deal_damage(t, ctx.base_damage())
	ctx.move_to_last(t)
