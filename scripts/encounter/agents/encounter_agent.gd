## Decides what an individual does on its turn.
##
## The seam between the encounter LOOP ([EncounterManager]) and the DECISION. The manager
## always does `await agent.decide(...)`: a synchronous implementation ([AutoAgent])
## answers at once and the encounter resolves in one go, headless and testable; one that
## waits for a person ([UiAgent]) suspends the loop until a choice arrives.
##
## Because both go through the same await, the loop is written once and never branches on
## who is playing.
class_name EncounterAgent
extends RefCounted


## The individual's action this turn, or null if it can do nothing at all.
## May be a coroutine — the manager awaits the result either way.
func decide(_individual: EncounterIndividual, _manager: EncounterManager) -> EncounterAction:
	return null
