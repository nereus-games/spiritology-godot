## Self-Denial — yilir · Variable · [ETH loss, change weakness]
## MÉCANIQUE : le rival ciblé perd un peu d'ETH chaque tour (TODO : récurrence) ; ses trois
## faiblesses deviennent l'énergie de cette capacité jusqu'à la fin de la rencontre ; il peut
## annuler ces effets en Méditant.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var t = ctx.primary()
	if t:
		ctx.drain_eth(t, ctx.dmg(&"small"))
		ctx.set_weakness(t, ctx.energy())  # les 3 faiblesses = énergie de la capacité
