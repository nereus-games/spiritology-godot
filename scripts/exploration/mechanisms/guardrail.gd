## Rambarde (garde-corps) : protège le bord d'un étage.
##
## Doc Notion (Level Design / Walls + Decors, section Guardrails) : géométriquement, c'est une
## porte qui ne s'ouvre jamais — [constant DungeonManager.EDGE_THICKNESS] posés sur l'ARÊTE
## entre deux cases, et non une case entière. Elle empêche donc de franchir ce bord (et de
## tomber), pour le joueur comme pour les rivaux, sans coûter de case ni gêner la circulation
## de part et d'autre.
##
## Basse ([constant HEIGHT] contre 1 m pour un mur) : on voit par-dessus, donc elle ne coupe pas
## la ligne de vue — c'est ce qui la distingue d'un mur de bord.
##
## Pas de `class_name` (voir dungeon_mechanism.gd) : `extends` par chemin.
extends "res://scripts/exploration/mechanisms/dungeon_mechanism.gd"

## Hauteur du garde-corps (mètres) : sous les yeux du duo ([constant DungeonManager.EYE_HEIGHT]).
const HEIGHT := 0.3
## Largeur du garde-corps : presque toute l'arête, en laissant un jour aux montants.
const WIDTH := 0.9

## Bord protégé : la rambarde est sur l'arête entre [member cell] et `cell + edge_dir`.
## Toujours une direction horizontale unitaire (±X ou ±Z).
@export var edge_dir := Vector3i(0, 0, 1)


## Sur l'arête, pas sur la case : les deux cases voisines restent utilisables.
func _register() -> void:
	_dungeon.register_edge_mechanism(cell, cell + edge_dir, self)


func _unregister() -> void:
	_dungeon.unregister_edge_mechanism(cell, cell + edge_dir, self)


## Une rambarde barre son arête en permanence (elle ne s'ouvre jamais).
func blocks_walk() -> bool:
	return true


## Basse : on voit (et on agit) par-dessus, contrairement à un mur ou à une porte fermée.
func blocks_sight() -> bool:
	return false


## Couleur sur la mini-map : gris clair de décor, et non l'orange des mécanismes avec lesquels
## le joueur interagit (une rambarde ne s'actionne pas).
func map_color() -> Color:
	return Color(0.55, 0.57, 0.62)


func _spawn_visual() -> void:
	var thin := DungeonManager.EDGE_THICKNESS
	var size := Vector3(WIDTH, HEIGHT, WIDTH)
	if edge_dir.x != 0:
		size.x = thin
	else:
		size.z = thin
	var offset := Vector3(edge_dir.x, 0.0, edge_dir.z) * DungeonManager.CELL_SIZE * 0.5
	_add_marker_box(Color(0.62, 0.64, 0.70), size, offset)
