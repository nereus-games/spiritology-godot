## Reactive Depreciation — fonéchal · normal · [ETH loss, limit actions]
## MÉCANIQUE : (requiert qu'un tour soit passé et que le user ait déjà agi) le dernier rival
## ayant utilisé une action/énergie différente de celle du user perd X ETH ; s'il n'a alors
## plus d'ETH, il perd une action au tour suivant. (Sélection historique : approximée à un
## rival au hasard.)
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var t = ctx.random_opponent()
	if t == null:
		return
	ctx.drain_eth(t, ctx.dmg(&"small"))
	if t.eth == 0:
		ctx.limit_actions(t, 1)
