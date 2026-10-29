## Shadow Work — spodra · Arcane · a lot · single use · [examine bonus, recover ETH]
## MECHANIC: not on turn 1. The user gets info on every species in the encounter, and gains X ETH
## if its weakness is Arcane or hidden from the rivals.
##
## "Info on every species" is one Examine per species present, not per individual: two rivals of
## one species give its page the info once. Each carries `EXAMINE_BONUS_POINTS` of info bonus
## (`examine_yield.gd`): a single-use ability that costs "a lot" earns more than a plain Examine.
## Dissolved individuals are not examined, and only a player character's Examine of a rival earns
## IFP, so the user's own and its teammate's species earn none.
extends AbilityScript

const ExamineYield := preload("res://scripts/encounter/effects/examine_yield.gd")

## Placeholder: the doc gives no figure.
const EXAMINE_BONUS_POINTS := 2


func execute(ctx: EncounterContext) -> void:
	var seen: Dictionary = {}
	for f in ctx.all_individuals:
		if f.is_dissolved() or seen.has(f.species_id()):
			continue
		seen[f.species_id()] = true
		ExamineYield.examine(ctx, f, EXAMINE_BONUS_POINTS)
	if ctx.weakness_of(ctx.user) == GameEnums.Energy.ARCANE or ctx.user.weakness_hidden:
		ctx.recover_eth(ctx.user, ctx.dmg(&"normal"))
