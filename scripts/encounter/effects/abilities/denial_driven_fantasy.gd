## Denial-Driven Fantasy — yilir · Arcane · mini · [recover ETH]
## MÉCANIQUE : requiert que le user ait une faiblesse. Il récupère X ETH par individu ayant
## une faiblesse différente, sans faiblesse, ou à faiblesse cachée ; l'indicateur d'ordre du
## tour est masqué (UI).
extends AbilityScript

func execute(ctx: EncounterContext) -> void:
	var uw := ctx.weakness_of(ctx.user)
	if uw == GameEnums.Energy.NONE:
		return
	var count := ctx.others().filter(func(f):
		var w := ctx.weakness_of(f)
		return w != uw or w == GameEnums.Energy.NONE or f.weakness_hidden).size()
	ctx.recover_eth(ctx.user, ctx.dmg(&"small") * count)
	ctx.request_ui(&"hide_turn_order_bar", {})
