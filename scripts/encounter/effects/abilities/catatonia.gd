## Catatonia — niyat · Crystal · [examine bonus]
## MECHANIC: improves the user's Examine and Meditate next turn — more info, more ETH, more
## damage — with larger bonuses if it took damage this turn or the previous one, larger still if
## its own teammate dealt it.
##
## The damage is read from the encounter history: a turn being a round, "this turn or the
## previous one" is this round and the one before, and damage the user did to itself counts as
## damage taken. The bonus is one step, plus one if it was hurt, plus one more if a teammate was
## among those who hurt it.
##
## The Meditate clauses are built on the next-turn modifiers: each step makes the user's next
## Meditate recover that much more ETH and leave that much more of a damage bonus, a step being
## the per-condition damage step (`modifier_per_condition`, a placeholder: the doc gives no
## figure). Unused, the boost is gone by the turn after.
##
## TODO: the Examine's own yield. Only the info bonus is granted, and it is merely logged:
## nothing consumes it, because an Examine yields no amount yet (roadmap, section 4).
extends AbilityScript

const NextTurnModifiers := preload("res://scripts/encounter/effects/next_turn_modifiers.gd")

## Placeholder: the doc gives no figure. The bonus this ability granted before it looked at the
## damage, now granted once per step.
const EXAMINE_BONUS_PER_STEP := 2


func execute(ctx: EncounterContext) -> void:
	var steps := _steps(ctx)
	ctx.grant_examine_bonus(ctx.user, EXAMINE_BONUS_PER_STEP * steps)
	NextTurnModifiers.boost_next_meditate(ctx, ctx.user, steps)


## 1, 2 if the user was hurt recently, 3 if a teammate was among those who hurt it.
func _steps(ctx: EncounterContext) -> int:
	if ctx.history.hurt_recently_by_teammate(ctx.user):
		return 3
	if ctx.history.hurt_recently(ctx.user):
		return 2
	return 1
