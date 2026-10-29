## The corruptible agent of the Coal Vetch, standing on its tile in a dungeon that has one.
##
## An obstacle, like a refresh crystal: with the player adjacent and facing it, the bribe is on
## offer for as long as an agent is still to arrive. Paying delays them all and makes the next
## bribe dearer; the price and the delay are the director's business (`coal_vetch.gd`), which
## sets [member director] when it places this mechanism.
##
## No `class_name`: `extends` by path. References the GameSession autoload.
extends "res://scripts/exploration/mechanisms/dungeon_mechanism.gd"

const ExplorationAction := preload("res://scripts/exploration/exploration_action.gd")

## The Coal Vetch of this dungeon, `coal_vetch.gd`. Set BEFORE the mechanism enters the tree.
var director


func blocks_walk() -> bool:
	return true


## Offered while an agent is still to arrive; the price is told when the bribe is tried.
func on_adjacent_actions(_who: Node, _facing: Vector3i) -> Array:
	if director == null or director.pending_count() == 0:
		return []
	return [ExplorationAction.new(&"bribe_agent", "UI_ACTION_BRIBE_AGENT", Callable(self, "bribe"))]


## Tries the bribe, and tells the player how it went. Returns whether it was paid.
func bribe() -> bool:
	if director == null:
		return false
	var price: int = director.price()
	if not director.can_bribe():
		_dungeon.post_message(tr("UI_VETCH_BRIBE_POOR") % price)
		return false
	director.pay()
	_dungeon.post_message(
		tr("UI_VETCH_BRIBE_PAID") % [price, BalanceData.current().coal_vetch_delay_turns]
	)
	return true


## Nothing left to delay.
func is_spent() -> bool:
	return director != null and director.pending_count() == 0


func _spawn_visual() -> void:
	_add_marker(Color(0.55, 0.25, 0.1), 0.9, 0.5)
