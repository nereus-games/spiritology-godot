## Effort of Neutrality — forlorn érzélak · Fluid · normal · usage unique · [change weakness]
## MÉCANIQUE : le user n'a plus de faiblesse jusqu'à son prochain tour ; si l'action du
## coéquipier n'inflige pas de dégâts, il perd aussi sa faiblesse (condition d'action future
## approximée : appliquée aux alliés).
extends AbilityScript

func execute(ctx: EncounterContext) -> void:
	ctx.remove_weakness(ctx.user)
	for a in ctx.allies():
		ctx.remove_weakness(a)  # TODO : seulement si l'action de l'allié n'inflige pas de dégâts
