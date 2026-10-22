## Self-Denial — yilir · Variable · [ETH loss, change weakness]
## MECHANIC: the targeted rival loses a little ETH every turn; all three of its weaknesses become
## this ability's energy for the rest of the encounter; and it can clear both effects by
## Meditating.
##
## The doc is silent on when the drain starts. The rival loses ETH when the ability lands and
## again at the start of each of its own turns, the amount being the one the first drain uses.
## Meditating ends the drain and gives the rival back the weaknesses its position implies.
extends AbilityScript

const OneOffs := preload("res://scripts/encounter/effects/one_off_rules.gd")


func execute(ctx: EncounterContext) -> void:
	var t = ctx.primary()
	if t:
		ctx.drain_eth(t, ctx.dmg(&"small"))
		# All 3 weaknesses become the ability's energy.
		ctx.set_weakness(t, ctx.energy(), EncounterIndividual.FOR_ENCOUNTER)
		OneOffs.recur_each_turn(ctx, t)


func recur(ctx: EncounterContext) -> void:
	if not ctx.targets.is_empty():
		ctx.drain_eth(ctx.targets[0], ctx.dmg(&"small"))


func on_meditated(ctx: EncounterContext) -> bool:
	ctx.reset_weakness(ctx.targets[0])
	return true
