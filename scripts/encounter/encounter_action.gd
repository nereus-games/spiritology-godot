## What a fighter chose to do this turn.
##
## The shared vocabulary between the agents that DECIDE ([EncounterAgent]) and the manager
## that APPLIES. The list comes from the design doc, Game Design / Encounters: "Talk,
## Examine, Use Ability (Challenge), Use / Give Object, Meditate".
##
## [constant Kind.PASS] is the doc's "…" action: offered only when nothing else is, and it
## passes the turn WITHOUT giving up your place in the order.
##
## [constant Kind.FLEE] is a menu action but never offered by default — the doc calls it a
## "special action from Abilities + Talents". Two separate routes reach it:
##   - a talent ADDS it, on its own terms: `run_away_2` (zuk) offers it permanently in
##     place of Talk and always succeeds; `slick_merchant` (fopin) offers it only on the
##     first turn or below 10 % DEN, for 10 ETH, and behind a QTE that can fail;
##   - an ability RUNS it directly, bypassing the menu — [method EncounterContext.flee],
##     called by `ghosting` and `opening_up_closing`.
## ## TODO: neither route actually leaves the encounter. Both end at the same wall —
## fleeing means teleporting 3-5 cells away in exploration, with a 50 % chance the rival
## disappears, and that is unbuilt. See docs/roadmap.md.
class_name EncounterAction
extends RefCounted

## [constant Kind.STEAL], like FLEE, is added to the menu by a talent — `steal` (granop)
## offers it in place of Talk. It takes an object from the target, at the risk of summoning
## a member of the Coal Vetch. Neither rivals carrying objects nor the Coal Vetch exists.
enum Kind { ABILITY, TALK, EXAMINE, MEDITATE, USE_OBJECT, FLEE, STEAL, PASS }

var kind: Kind = Kind.ABILITY
var ability: AbilityData = null  ## Kind.ABILITY uniquement
var targets: Array = []  ## EncounterFighter visés
var object_id: StringName = &""  ## Kind.USE_OBJECT uniquement


static func use_ability(p_ability: AbilityData, p_targets: Array) -> EncounterAction:
	var a := EncounterAction.new()
	a.kind = Kind.ABILITY
	a.ability = p_ability
	a.targets = p_targets
	return a


static func of_kind(p_kind: Kind, p_targets: Array = []) -> EncounterAction:
	var a := EncounterAction.new()
	a.kind = p_kind
	a.targets = p_targets
	return a


## A short label for debugging. Text meant for the player goes through translation keys,
## never through here.
func label() -> String:
	if kind == Kind.ABILITY:
		return String(ability.id) if ability else "?"
	return String(Kind.keys()[kind]).to_lower()
