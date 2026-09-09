## Mur fissuré (franchissement Cranny Crossing).
##
## Doc Notion (Level Design / Walls + Decors « Cracked Wall »). Un mur d'exactement une case
## d'épaisseur est représenté fissuré et peut être traversé grâce à la capacité d'exploration
## Cranny Crossing. Le mécanisme occupe la case du mur ; depuis la case adjacente en le
## regardant, le joueur peut traverser vers la case située DERRIÈRE (mur + direction).
##
## Pas de `class_name` : `extends` par chemin. Référence l'autoload GameSession.
extends "res://scripts/exploration/mechanisms/dungeon_mechanism.gd"

const ExplorationAction := preload("res://scripts/exploration/exploration_action.gd")

## Id de la capacité d'exploration requise (usage unique par visite comme les autres).
const CRANNY_ABILITY := &"cranny_crossing"

## Un mur reste infranchissable au pas normal (on le traverse via l'action).
func blocks_walk() -> bool:
	return true

## Propose la traversée si la capacité n'a pas été utilisée et que la case au-delà (mur +
## direction regardée) est franchissable.
func on_adjacent_actions(who: Node, facing: Vector3i) -> Array:
	if GameSession.is_exploration_ability_used(CRANNY_ABILITY):
		return []
	var beyond := cell + facing
	if _dungeon == null or not _dungeon.is_walkable(beyond):
		return []
	return [ExplorationAction.new(&"cranny_crossing", "UI_ACTION_CRANNY_CROSSING", Callable(self, "cross").bind(who, facing))]

## Traverse le mur : place le joueur sur la case au-delà et consomme la capacité.
func cross(who: Node, facing: Vector3i) -> void:
	if GameSession.is_exploration_ability_used(CRANNY_ABILITY):
		return
	var beyond := cell + facing
	if _dungeon == null or not _dungeon.is_walkable(beyond):
		return
	if who.has_method("teleport_to"):
		who.teleport_to(beyond)
	GameSession.mark_exploration_ability_used(CRANNY_ABILITY)

func _spawn_visual() -> void:
	_add_marker(Color(0.3, 0.28, 0.32), 0.95, 0.95)  # mur sombre, fissuré (une case pleine)
