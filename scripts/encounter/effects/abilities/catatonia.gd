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
## TODO: the improvement itself. Only the Examine info bonus is granted, and it is merely logged:
## nothing consumes it. Examine's yield, Meditate's ETH and Meditate's damage bonus all wait for
## next-turn modifiers on the individual (roadmap, section 2); once they exist, scale them by the
## same steps.
extends AbilityScript

## Placeholder: the doc gives no figure. The bonus this ability granted before it looked at the
## damage, now granted once per step.
const EXAMINE_BONUS_PER_STEP := 2


func execute(ctx: EncounterContext) -> void:
	ctx.grant_examine_bonus(ctx.user, EXAMINE_BONUS_PER_STEP * _steps(ctx))


## 1, 2 if the user was hurt recently, 3 if a teammate was among those who hurt it.
func _steps(ctx: EncounterContext) -> int:
	if ctx.history.hurt_recently_by_teammate(ctx.user):
		return 3
	if ctx.history.hurt_recently(ctx.user):
		return 2
	return 1
