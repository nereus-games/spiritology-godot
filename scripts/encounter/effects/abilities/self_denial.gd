## Self-Denial — yilir · Variable · [ETH loss, change weakness]
## MECHANIC: the targeted rival loses a little ETH every turn (the recurrence is a TODO); all
## three of its weaknesses become this ability's energy for the rest of the encounter; and it can
## clear both effects by Meditating.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var t = ctx.primary()
	if t:
		ctx.drain_eth(t, ctx.dmg(&"small"))
		ctx.set_weakness(t, ctx.energy())  # all 3 weaknesses become the ability's energy
