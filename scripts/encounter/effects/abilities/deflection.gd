## Deflection — kalilk · Random · medium · [change weakness, damage reduction/increase]
## MÉCANIQUE : (requiert que le user n'ait pas utilisé deux fois la même action). La faiblesse
## de la cible devient l'énergie de cette capacité jusqu'à son prochain tour ; les dégâts de
## type-faiblesse sont doublés pour tous ce tour (doublement global : TODO).
extends AbilityScript

func execute(ctx: EncounterContext) -> void:
	var t = ctx.primary()
	if t:
		ctx.set_weakness(t, ctx.energy())
	# TODO : doubler les dégâts correspondant à la faiblesse de chacun ce tour.
