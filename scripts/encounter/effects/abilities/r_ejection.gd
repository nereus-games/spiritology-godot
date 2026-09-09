## (R)ejection — sénskor · Fluid · medium · [change weakness]
## MÉCANIQUE : la faiblesse du user est cachée aux rivaux jusqu'à son prochain tour ; au
## hasard (50 %) il perd sa faiblesse OU retrouve sa faiblesse par défaut (annulant une
## modification du tour) ; il est immunisé aux dégâts Fluide et Toxique jusqu'à son prochain tour.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	ctx.hide_weakness(ctx.user)
	if ctx.rng.randf() < 0.5:
		ctx.remove_weakness(ctx.user)
	else:
		ctx.reset_weakness(ctx.user)
	ctx.grant_immunity(ctx.user, [GameEnums.Energy.FLUID, GameEnums.Energy.TOXIC])
