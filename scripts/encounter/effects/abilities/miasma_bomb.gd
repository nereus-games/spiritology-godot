## Miasma Bomb — hibulus · Random · mini/small · usage unique · [damage, limit actions]
## MECHANIC: the user and its teammates take mini damage, the rivals small; abilities that are
## neither Toxic nor Fluid are unavailable next turn, to everyone.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	for m in ctx.team():
		ctx.deal_damage(m, ctx.dmg(&"mini"))
	for r in ctx.opponents():
		ctx.deal_damage(r, ctx.dmg(&"small"))
	for f in ctx.all_fighters:
		ctx.restrict_to(f, ["Toxic", "Fluid"])
