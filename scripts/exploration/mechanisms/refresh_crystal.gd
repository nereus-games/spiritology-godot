## Cristal de rafraîchissement.
##
## Doc Notion (Level Design / Mechanisms « Refresh Crystal »). Obstacle INDESTRUCTIBLE
## présent vers la mi-parcours des grands donjons. Quand le joueur est adjacent ET le
## regarde, il peut réutiliser TOUTES ses capacités d'exploration déjà employées. Utilisable
## une seule fois par visite de donjon.
##
## Pas de `class_name` : `extends` par chemin. Référence l'autoload GameSession.
extends "res://scripts/exploration/mechanisms/dungeon_mechanism.gd"

const ExplorationAction := preload("res://scripts/exploration/exploration_action.gd")

var _used := false


## Obstacle indestructible : toujours infranchissable.
func blocks_walk() -> bool:
	return true


## Action « rafraîchir » disponible depuis une case adjacente en le regardant, tant qu'il
## n'a pas déjà servi cette visite. (La direction du regard est gérée par
## [method DungeonManager.actions_for] : le cristal est sur la case regardée.)
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


## Cristal déjà employé cette visite : plus rien à en tirer (règle transverse « épuisé »).
func is_spent() -> bool:
	return _used


## Rafraîchit toutes les capacités d'exploration utilisées (une seule fois par visite).
func refresh() -> void:
	if _used:
		return
	_used = true
	GameSession.refresh_all_exploration_abilities()
	# Éteint, mais toujours là : c'est un obstacle indestructible, donc on le grise SANS
	# l'aplatir (l'aplatir ferait croire qu'on peut passer).
	_grey_marker()


func reset_between_visits() -> void:
	_used = false
	_respawn_marker()  # de nouveau utilisable : il retrouve son cyan


func _spawn_visual() -> void:
	_add_marker(Color(0.3, 0.8, 0.85), 1.0, 0.5)  # cristal cyan, haut (occupe toute la case)
