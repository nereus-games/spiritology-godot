## Halo Effect — oléni · [examine bonus, recover ETH]
## MECHANIC: from turn 2 on, if an individual has the same weakness or took the same action as
## last turn, the user picks it and Examines it, with an info bonus per criterion met; the user
## and the target both recover X ETH.
##
## Read from the encounter history, one turn being one round. "Has the same weakness" is
## exposing now the one it exposed on its previous turn; "took the same action" is having done,
## this round, what it did on its previous turn — so an individual that has not acted yet this
## round can only qualify by its weakness. Passing is not an action, and having no weakness is not
## a weakness. The user cannot pick itself; it picks at random among those that qualify, and when
## none does, nothing happens at all, ETH included.
##
## The Examine is a real one (see `examine_yield.gd`): when a player character uses this on a
## rival, the rival's species yields the Examine's IFP times the bonus, `BONUS_PER_CRITERION`
## points per criterion met, on top of any bonus the user already carries and its talents'. Picking
## a teammate, or being a rival, earns no IFP; the ETH is recovered all the same.
extends AbilityScript

const ExamineYield := preload("res://scripts/encounter/effects/examine_yield.gd")

## Placeholder: the doc gives no figure. It is the bonus this ability granted before it counted
## criteria, now granted once per criterion met.
const BONUS_PER_CRITERION := 2


func execute(ctx: EncounterContext) -> void:
	var picks: Array = []
	for other in ctx.others():
		if _criteria_met(ctx, other) > 0:
			picks.append(other)
	var t = ctx.random_of(picks)
	if t == null:
		ctx.note(String(TranslationServer.translate("LOG_HISTORY_NOBODY_REPEATS")))
		return
	ExamineYield.examine(ctx, t, BONUS_PER_CRITERION * _criteria_met(ctx, t))
	ctx.recover_eth(ctx.user, ctx.dmg(&"small"))
	ctx.recover_eth(t, ctx.dmg(&"small"))


## How many of the two criteria `who` meets: 0, 1 or 2. Both compare with a previous turn, so
## nobody meets either in the first round: "from turn 2 on" needs no rule of its own.
func _criteria_met(ctx: EncounterContext, who) -> int:
	var met := 0
	if ctx.history.repeated_weakness(who, ctx.weakness_of(who)):
		met += 1
	if ctx.history.repeated_action(who):
		met += 1
	return met
