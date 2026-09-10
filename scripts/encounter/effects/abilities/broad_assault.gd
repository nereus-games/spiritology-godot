## Broad Assault — basipik · Variable · medium · small (7) · [damage]
## MECHANIC: the ability's energy is the user's current weakness; two random rivals take
## damage.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	ctx.set_energy(ctx.weakness_of(ctx.user))
	for t in ctx.random_opponents(2):
		ctx.deal_damage(t, ctx.base_damage())
