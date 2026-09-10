## The player's agent: suspends the loop until [method submit].
##
## The contract with the encounter UI. On the fighter's turn, [signal choice_requested]
## fires and the UI opens its menu; the loop stays suspended until the UI calls
## [method submit] with a choice. What may be offered is read from the manager —
## [method EncounterManager.usable_abilities], [method EncounterManager.candidate_targets].
class_name UiAgent
extends EncounterAgent

## The loop is waiting on a choice for `fighter`.
signal choice_requested(fighter: EncounterFighter, manager: EncounterManager)

signal _submitted(action: EncounterAction)

## Whose choice is awaited, or null when the loop is not waiting.
var pending_fighter: EncounterFighter = null


func decide(fighter: EncounterFighter, manager: EncounterManager) -> EncounterAction:
	pending_fighter = fighter
	# DEFERRED on purpose. A handler that answers immediately — "no ability is playable",
	# so submit at once — would call submit() before the await below was even reached: the
	# signal would go nowhere and the encounter would hang. Deferring guarantees the loop
	# is suspended before anyone can answer it.
	choice_requested.emit.call_deferred(fighter, manager)
	var action: EncounterAction = await _submitted
	pending_fighter = null
	return action


## Hands the choice back and resumes the loop. `null` means the fighter can do nothing.
## Only valid in answer to [signal choice_requested].
func submit(action: EncounterAction) -> void:
	_submitted.emit(action)
