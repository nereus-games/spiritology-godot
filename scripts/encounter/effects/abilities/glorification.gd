## Glorification — malcouli · [change weakness, recover ETH]
## MÉCANIQUE : le user adopte la faiblesse de la cible (approx. des 3) et gagne de l'ETH :
## peu si coéquipier, plus si rival de même origine, encore plus si rival d'origine différente.
## (Perte de cet ETH si la cible le blesse ensuite : TODO.)
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var t = ctx.primary()
	if t == null:
		return
	ctx.set_weakness(ctx.user, ctx.weakness_of(t))
	var amount: int
	if t.is_player == ctx.user.is_player:
		amount = ctx.dmg(&"small")
	elif t.species and ctx.user.species and t.species.spiricosm == ctx.user.species.spiricosm:
		amount = ctx.dmg(&"normal")
	else:
		amount = ctx.dmg(&"big")
	ctx.recover_eth(ctx.user, amount)
