## The turn order of an encounter.
##
## Drawn at RANDOM when the encounter begins ("Turn order is defined at random when the
## encounter begins"), then changed by abilities such as Shuffle and Tumult.
##
## It decides each individual's POSITION — first, in-between, last — and therefore which of
## its three weaknesses is exposed. That is what makes reordering an attack rather than a
## flourish.
##
## The doc's rule when several reordering effects land in one turn: only the LAST counts.
## Requests are therefore held and applied at the end of the turn ([method apply_pending]).
class_name EncounterTimeline
extends RefCounted

var order: Array = []  ## The EncounterIndividuals, in turn order
var _pending: Variant = null  ## The last reordering asked for this turn; last wins


## Sets the initial order. Pass the manager's seeded `rng` to draw it at random as the doc
## wants; without one, the order stays as given — which is what tests rely on.
func setup(individuals: Array, rng: RandomNumberGenerator = null) -> void:
	order = individuals.duplicate()
	if rng != null:
		_shuffle(order, rng)
	_pending = null


## Fisher-Yates in place, driven by a seeded rng and therefore reproducible.
static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


func position_of(individual) -> GameEnums.TurnPosition:
	var i := order.find(individual)
	if i <= 0:
		return GameEnums.TurnPosition.FIRST
	if i >= order.size() - 1:
		return GameEnums.TurnPosition.LAST
	return GameEnums.TurnPosition.MIDDLE


## Requests a whole new order. Applied at end of turn, and the last request wins.
func request_reorder(new_order: Array) -> void:
	_pending = new_order.duplicate()


## Requests that `individual` go last next turn.
func request_move_last(individual) -> void:
	var o: Array = (_pending if _pending != null else order).duplicate()
	o.erase(individual)
	o.append(individual)
	_pending = o


## Requests that `individual` go first next turn.
func request_move_first(individual) -> void:
	var o: Array = (_pending if _pending != null else order).duplicate()
	o.erase(individual)
	o.push_front(individual)
	_pending = o


## Requests a reshuffle — Shuffle, Tumult.
func request_shuffle(rng: RandomNumberGenerator) -> void:
	var shuffled := order.duplicate()
	_shuffle(shuffled, rng)
	_pending = shuffled


## Applies whatever reordering is pending. True if the order actually changed.
func apply_pending() -> bool:
	if _pending == null:
		return false
	order = _pending
	_pending = null
	return true


## Individuals still standing.
func living() -> Array:
	return order.filter(func(f): return not f.is_dissolved())
