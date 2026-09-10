## A cracked wall, crossed with Cranny Crossing.
##
## From the design doc ("Walls + Decors / Cracked Wall"). A wall exactly one tile thick is drawn
## cracked and can be crossed with the Cranny Crossing exploration ability. The mechanism
## occupies the wall's tile; from the adjacent tile, facing it, the player can cross to the tile
## BEHIND it (wall plus direction).
##
## No `class_name`: `extends` by path. References the GameSession autoload.
extends "res://scripts/exploration/mechanisms/dungeon_mechanism.gd"

const ExplorationAction := preload("res://scripts/exploration/exploration_action.gd")

## The exploration ability required. Once per visit, like the others.
const CRANNY_ABILITY := &"cranny_crossing"


## A wall stays impassable to an ordinary step; crossing goes through the action.
func blocks_walk() -> bool:
	return true


## Offers the crossing when the ability is unspent and the tile beyond — the wall plus the
## direction being faced — is walkable.
func on_adjacent_actions(who: Node, facing: Vector3i) -> Array:
	if GameSession.is_exploration_ability_used(CRANNY_ABILITY):
		return []
	var beyond := tile + facing
	if _dungeon == null or not _dungeon.is_walkable(beyond):
		return []
	return [
		ExplorationAction.new(
			&"cranny_crossing",
			"UI_ACTION_CRANNY_CROSSING",
			Callable(self, "cross").bind(who, facing)
		)
	]


func cross(who: Node, facing: Vector3i) -> void:
	if GameSession.is_exploration_ability_used(CRANNY_ABILITY):
		return
	var beyond := tile + facing
	if _dungeon == null or not _dungeon.is_walkable(beyond):
		return
	if who.has_method("teleport_to"):
		who.teleport_to(beyond)
	GameSession.mark_exploration_ability_used(CRANNY_ABILITY)


func _spawn_visual() -> void:
	_add_marker(Color(0.3, 0.28, 0.32), 0.95, 0.95)  # a dark cracked wall filling the tile
