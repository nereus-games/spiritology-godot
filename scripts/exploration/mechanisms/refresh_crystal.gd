## A refresh crystal.
##
## From the design doc ("Mechanisms / Refresh Crystal"). An INDESTRUCTIBLE obstacle found around
## the midpoint of the larger dungeons. With the player adjacent AND facing it, every exploration
## ability already spent becomes usable again. Once per dungeon visit.
##
## No `class_name`: `extends` by path. References the GameSession autoload.
extends "res://scripts/exploration/mechanisms/dungeon_mechanism.gd"

const ExplorationAction := preload("res://scripts/exploration/exploration_action.gd")

var _used := false


## An indestructible obstacle: never passable.
func blocks_walk() -> bool:
	return true


## The refresh action, offered from an adjacent tile while facing it and while it has not been
## used this visit. Facing is handled by [method DungeonManager.actions_for]: the crystal is on
## the tile being looked at.
func on_adjacent_actions(_who: Node, _facing: Vector3i) -> Array:
	if _used:
		return []
	return [
		ExplorationAction.new(
			&"refresh_crystal", "UI_ACTION_REFRESH_CRYSTAL", Callable(self, "refresh")
		)
	]


func is_used() -> bool:
	return _used


## Already used this visit, so nothing left to get out of it.
func is_spent() -> bool:
	return _used


## Refreshes every spent exploration ability. Once per visit.
func refresh() -> void:
	if _used:
		return
	_used = true
	GameSession.refresh_all_exploration_abilities()
	# Dead but still there: it is an indestructible obstacle, so grey it out WITHOUT flattening
	# it — flattening would suggest you can walk through.
	_grey_marker()


func reset_between_visits() -> void:
	_used = false
	_respawn_marker()  # usable again: it gets its cyan back


func _spawn_visual() -> void:
	_add_marker(Color(0.3, 0.8, 0.85), 1.0, 0.5)  # a tall cyan crystal, filling the tile
