## Social Capital — oléni · normal · [change weakness, recover ETH]
## MÉCANIQUE : un coéquipier ciblé gagne X ETH par individu de la rencontre (hors lui et le
## user) ; le user peut (ou non) lui choisir une nouvelle faiblesse parmi 2.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var allies := ctx.allies()
	var t = ctx.random_of(allies) if not allies.is_empty() else ctx.user
	var n := ctx.others().filter(func(f): return f != t).size()
	ctx.recover_eth(t, ctx.dmg(&"small") * n)
	ctx.change_weakness(t)  # choix optionnel d'une nouvelle faiblesse
