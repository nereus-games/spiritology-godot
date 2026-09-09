## Denial-Driven Fantasy — yilir · Arcane · mini · [recover ETH]
## MÉCANIQUE : requiert que le user ait une faiblesse. Il récupère X ETH par individu ayant
## une faiblesse différente, sans faiblesse, ou à faiblesse cachée ; l'indicateur d'ordre du
## tour est masqué (UI).
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var uw := ctx.weakness_of(ctx.user)
	if uw == GameEnums.Energy.NONE:
		return
	# Boucle explicite plutôt qu'un filter() à lambda multi-lignes : gdformat casse ce
	# dernier quand il est enchaîné (.others().filter(...).size()), et le résultat ne
	# compile plus. Même sémantique, et plus lisible.
	var count := 0
	for f in ctx.others():
		var w := ctx.weakness_of(f)
		if w != uw or w == GameEnums.Energy.NONE or f.weakness_hidden:
			count += 1
	ctx.recover_eth(ctx.user, ctx.dmg(&"small") * count)
	ctx.request_ui(&"hide_turn_order_bar", {})
