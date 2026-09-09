## Ordre du tour d'une rencontre.
##
## Tiré au HASARD au début de la rencontre (règle Notion : « Turn order is defined at
## random when the encounter begins »), puis modifiable par des capacités (Shuffle,
## Tumult…). Détermine la POSITION de chaque combattant (first / in-between / last), dont
## dépend sa faiblesse active. Règle Notion : si plusieurs effets d'ordre s'appliquent dans
## un même tour, seul le DERNIER compte → les demandes de réordonnancement sont mises en
## attente et appliquées en fin de tour ([method apply_pending]).
class_name EncounterTimeline
extends RefCounted

var order: Array = []  ## EncounterFighter, dans l'ordre du tour
var _pending: Variant = null  ## dernier réordonnancement demandé ce tour (last-wins)


## Pose l'ordre initial. Passer le `rng` (seedé) du manager pour le tirer au hasard comme
## le veut la doc ; sans `rng`, l'ordre reste celui de `fighters` (tests, cas déterministes).
func setup(fighters: Array, rng: RandomNumberGenerator = null) -> void:
	order = fighters.duplicate()
	if rng != null:
		_shuffle(order, rng)
	_pending = null


## Mélange Fisher-Yates en place, piloté par un rng seedé (donc reproductible).
static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


## Position d'un combattant : FIRST (tête), LAST (queue), sinon MIDDLE.
func position_of(fighter) -> GameEnums.TurnPosition:
	var i := order.find(fighter)
	if i <= 0:
		return GameEnums.TurnPosition.FIRST
	if i >= order.size() - 1:
		return GameEnums.TurnPosition.LAST
	return GameEnums.TurnPosition.MIDDLE


## Demande un nouvel ordre (appliqué en fin de tour ; le dernier appel gagne).
func request_reorder(new_order: Array) -> void:
	_pending = new_order.duplicate()


## Demande que `fighter` soit en queue de l'ordre du prochain tour.
func request_move_last(fighter) -> void:
	var o: Array = (_pending if _pending != null else order).duplicate()
	o.erase(fighter)
	o.append(fighter)
	_pending = o


## Demande que `fighter` soit en tête de l'ordre du prochain tour.
func request_move_first(fighter) -> void:
	var o: Array = (_pending if _pending != null else order).duplicate()
	o.erase(fighter)
	o.push_front(fighter)
	_pending = o


## Demande un mélange aléatoire de l'ordre (Shuffle/Tumult).
func request_shuffle(rng: RandomNumberGenerator) -> void:
	var shuffled := order.duplicate()
	_shuffle(shuffled, rng)
	_pending = shuffled


## Applique le réordonnancement en attente (fin de tour). Renvoie true si changé.
func apply_pending() -> bool:
	if _pending == null:
		return false
	order = _pending
	_pending = null
	return true


## Combattants encore en lice (non dissous).
func living() -> Array:
	return order.filter(func(f): return not f.is_dissolved())
