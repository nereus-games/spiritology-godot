## Escalier (porté du proto Unity, PlayerController.TryMove).
##
## Détecté au DÉPLACEMENT : quand le joueur avance vers la case d'un escalier, il est porté
## à `position + direction × 2 + changement d'étage` (2 cases plus loin, un étage plus haut ou
## plus bas). On n'atterrit donc jamais SUR l'escalier. UpStairs (`level_delta = +1`) et
## DownStairs (`level_delta = -1`) sont deux cases (bas et haut) formant le même escalier.
##
## La case de l'escalier n'est PAS du sol (on ne s'y arrête pas, on est porté au-delà).
##
## ## TODO(dungeon checker): la doc pose deux contraintes de level design qui ne sont vérifiées
## nulle part — un escalier doit mener à du sol (normal ou spécial), et la case DIRECTEMENT
## au-dessus de lui doit être vide. Le bloc de marches monte jusqu'à [constant
## DungeonManager.CELL_SIZE] : un sol posé par-dessus le traverserait sans un mot. À reprendre
## avec le validateur de donjon (même chantier que le pont étroit et les trous sans fond).
##
## Pas de `class_name` : `extends` par chemin.
extends "res://scripts/exploration/mechanisms/dungeon_mechanism.gd"

## +1 = escalier montant, -1 = escalier descendant.
@export var level_delta := 1
## Direction horizontale que « regarde » l'escalier (pour l'orientation du visuel).
@export var face_dir := Vector3i(0, 0, 1)


## Case d'arrivée quand on avance vers cet escalier depuis `from_cell` dans la direction
## `delta` : 2 cases plus loin + changement d'étage (modèle Unity `pos + dir*2 + up/down`).
func stairs_destination(from_cell: Vector3i, delta: Vector3i) -> Vector3i:
	return from_cell + delta * 2 + Vector3i(0, level_delta, 0)


# --- Changement d'étage (interface commune, cf. DungeonMechanism) ---


func has_level_link() -> bool:
	return true


## On aborde un escalier depuis la case située dans son dos, en marchant vers lui.
func level_link_from() -> Vector3i:
	return cell - face_dir


func level_link_to() -> Vector3i:
	return stairs_destination(level_link_from(), face_dir)


## Un escalier se prend en ENTRANT dedans depuis la case d'abord.
func level_link_needs_step_in() -> bool:
	return true


## Nombre de marches (proto Unity : forme ProBuilder « Stairs » de 6 marches).
const STEP_COUNT := 6


## Visuel : un BLOC PLEIN de la taille d'une case, taillé en marches sur sa face avant (modèle
## du proto Unity : ProBuilder Stairs 1×1×1, 6 marches, côtés fermés). Vu de côté ou de
## derrière, c'est donc une masse, pas une enfilade de marches flottantes. La première marche
## part du BORD de la case ; la dernière atteint le sol de l'étage supérieur.
##
## Rendu uniquement par la case MONTANTE (les deux cases, empilées, forment le même escalier).
func _spawn_visual() -> void:
	if level_delta < 0:
		return
	var hdir := Vector3(face_dir.x, 0.0, face_dir.z)
	if hdir.length() < 0.5:
		hdir = Vector3(0.0, 0.0, 1.0)
	var side := Vector3(absf(hdir.z), 0.0, absf(hdir.x))  # axe transversal (largeur de case)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.62, 0.9)
	var cs := DungeonManager.CELL_SIZE
	var run := cs / float(STEP_COUNT)  # profondeur d'une marche
	for i in range(STEP_COUNT):
		# Tranche i : de la marche i à la suivante en profondeur, pleine depuis le sol jusqu'à
		# sa hauteur (c'est ce remplissage qui donne le bloc plein).
		var rise := cs * float(i + 1) / float(STEP_COUNT)
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = hdir.abs() * run + side * cs + Vector3(0.0, rise, 0.0)
		mi.mesh = box
		mi.material_override = mat
		# Origine du nœud = sol de la case, en son centre : on part du bord opposé à la montée.
		mi.position = hdir * (-cs * 0.5 + run * (float(i) + 0.5)) + Vector3(0.0, rise * 0.5, 0.0)
		add_child(mi)
