## Priming — fopin · Variable · medium · [change next TO, change weakness, immunity]
## MÉCANIQUE : un coéquipier ciblé passe premier au prochain tour et adopte l'énergie de
## cette capacité comme faiblesse ; jusqu'au prochain tour du user, les dégâts des coéquipiers
## montent d'un cran (mini→small→normal→big) et ils obtiennent plus d'info. (Boost de dégâts
## sortants et info : TODO.)
extends AbilityScript

func execute(ctx: EncounterContext) -> void:
	var t = ctx.random_of(ctx.allies())
	if t:
		ctx.move_to_first(t)
		ctx.set_weakness(t, ctx.energy())
