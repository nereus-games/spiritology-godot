## Troublesome Secret — basipik · mini (5) · [ETH loss, limit actions]
## MECHANIC: the targeted rival loses X ETH and can no longer use Examine or any Object for the
## rest of the encounter, or until it Meditates.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var t = ctx.primary()
	if t:
		ctx.drain_eth(t, ctx.dmg(&"small"))
		ctx.restrict_to(t, ["LOG_RESTRICT_EXCEPT_EXAMINE", "LOG_RESTRICT_EXCEPT_OBJECT"])
