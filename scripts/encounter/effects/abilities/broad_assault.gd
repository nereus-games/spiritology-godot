## Broad Assault — basipik · Variable · medium · small (7) · [damage]
## MÉCANIQUE : l'énergie de la capacité = faiblesse actuelle du user ;
## deux rivaux au hasard subissent des dégâts.
extends AbilityScript

func execute(ctx: EncounterContext) -> void:
	ctx.set_energy(ctx.weakness_of(ctx.user))
	for t in ctx.random_opponents(2):
		ctx.deal_damage(t, ctx.base_damage())
