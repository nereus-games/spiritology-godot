## The player's agent: suspends the loop until [method submit].
##
## The contract with the encounter UI. On the individual's turn, [signal choice_requested]
## fires and the UI opens its menu; the loop stays suspended until the UI calls
## [method submit] with a choice. What may be offered is read from the manager —
## [method EncounterManager.usable_abilities], [method EncounterManager.candidate_targets].
class_name UiAgent
extends EncounterAgent

## The loop is waiting on a choice for `individual`.
signal choice_requested(individual: EncounterIndividual, manager: EncounterManager)

signal _submitted(action: EncounterAction)

## Whose choice is awaited, or null when the loop is not waiting.
var pending_individual: EncounterIndividual = null


func decide(individual: EncounterIndividual, manager: EncounterManager) -> EncounterAction:
	pending_individual = individual
	# DEFERRED on purpose. A handler that answers immediately — "no ability is playable",
	# so submit at once — would call submit() before the await below was even reached: the
	# signal would go nowhere and the encounter would hang. Deferring guarantees the loop
	# is suspended before anyone can answer it.
	choice_requested.emit.call_deferred(individual, manager)
	var action: EncounterAction = await _submitted
	pending_individual = null
	return action


## Hands the choice back and resumes the loop. `null` means the individual can do nothing.
## Only valid in answer to [signal choice_requested].
func submit(action: EncounterAction) -> void:
	_submitted.emit(action)
