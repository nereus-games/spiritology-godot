## Miasma Bomb — hibulus · Random · mini/small · usage unique · [damage, limit actions]
## MÉCANIQUE : le user et ses coéquipiers subissent de petits dégâts (mini), les rivaux des
## dégâts moyens (small) ; les capacités non Toxiques ni Fluides sont indisponibles au tour
## suivant (pour tout le monde).
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	for m in ctx.team():
		ctx.deal_damage(m, ctx.dmg(&"mini"))
	for r in ctx.opponents():
		ctx.deal_damage(r, ctx.dmg(&"small"))
	for f in ctx.all_fighters:
		ctx.restrict_to(f, ["Toxic", "Fluid"])
