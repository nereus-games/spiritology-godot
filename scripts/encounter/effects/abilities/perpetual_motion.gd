## Perpetual Motion — forlorn matzal · [ETH loss → en fait recover ETH]
## MECHANIC: the target recovers X ETH, more if it has no weakness.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var t = ctx.primary()
	if t:
		var amount := (
			ctx.dmg(&"normal") if ctx.weakness_of(t) == GameEnums.Energy.NONE else ctx.dmg(&"small")
		)
		ctx.recover_eth(t, amount)
