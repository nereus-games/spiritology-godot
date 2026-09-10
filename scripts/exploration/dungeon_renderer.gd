## Dessin d'un donjon : transforme la grille LOGIQUE en maillages visibles.
##
## Séparé de [DungeonManager], qui tient le modèle — où est le sol, ce qui bloque, qui occupe
## quoi. Ce script n'en fait que des boîtes, et ne lit le donjon que par son API PUBLIQUE
## ([method DungeonManager.floor_cells], [method DungeonManager.pit_cells],
## [method DungeonManager.fall_landing]). C'est ce qui rend la frontière réelle : si le rendu
## a besoin d'une information, le modèle doit la nommer, pas la laisser traîner en privé.
##
## Pas de `class_name` (piège du cache de classes en CLI) : obtenu par `preload`.
extends RefCounted

const FLOOR_COLOR := Color(0.24, 0.24, 0.30)
const PIT_COLOR := Color(0.12, 0.12, 0.16)
const WALL_COLOR := Color(0.14, 0.14, 0.17)


## Pose la géométrie visible dans `dm` : un bloc de mur d'une case sur chaque case de
## `wall_cells`, et une DALLE MINCE (épaisseur [constant DungeonManager.FLOOR_THICKNESS], qui
## fait aussi office de plafond pour la case du dessous) sur chaque case de sol qui n'a PAS de
## mur en dessous — là où il y a un mur, c'est sa face haute qui sert de sol (doc « Walls +
## Decors »).
static func render_grid(dm, wall_cells: Dictionary) -> void:
	var floor_mat := _material(FLOOR_COLOR)
	for c in dm.floor_cells():
		if dm.pit_cells().has(c):
			continue  # dalle abaissée rendue plus bas (planche du pont posée par-dessus)
		if wall_cells.has(c + Vector3i.DOWN):
			continue  # un bloc de mur tient lieu de sol : pas de dalle par-dessus
		dm.add_child(_make_slab(dm, dm.cell_to_world(c), floor_mat))

	# Fosses : dalle de fond sombre en contrebas UNIQUEMENT s'il n'y a pas déjà un vrai sol
	# plus bas (sinon on masquerait le ravin dans lequel on est censé pouvoir tomber).
	var pit_mat := _material(PIT_COLOR)
	for c in dm.pit_cells():
		if dm.fall_landing(c) != c:
			continue  # un étage inférieur sert déjà de fond
		var pos: Vector3 = dm.cell_to_world(c) + Vector3(0.0, -dm.PIT_DEPTH, 0.0)
		dm.add_child(_make_slab(dm, pos, pit_mat))

	var wall_mat := _material(WALL_COLOR)
	for w in wall_cells:
		# Un mur surmonté d'une case de sol porte le revêtement de sol sur sa face haute :
		# c'est LUI le sol de l'étage au-dessus.
		var top_mat: StandardMaterial3D = (
			floor_mat if dm.floor_cells().has(w + Vector3i.UP) else null
		)
		dm.add_child(_make_wall_block(dm, dm.cell_to_world(w), wall_mat, top_mat))


## Rendu minimal d'une salle de démonstration : un sol plat d'un seul tenant, et des boîtes
## de murs sur le pourtour et les cases bloquées. Échafaudage, comme la salle elle-même.
static func build_demo_visuals(dm, width: int, depth: int, blocked: Dictionary) -> void:
	var floor_mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(width * dm.CELL_SIZE, depth * dm.CELL_SIZE)
	floor_mi.mesh = plane
	floor_mi.position = Vector3(
		(width - 1) * dm.CELL_SIZE * 0.5, 0.0, (depth - 1) * dm.CELL_SIZE * 0.5
	)
	dm.add_child(floor_mi)

	var wall_cells := {}
	for x in range(-1, width + 1):
		wall_cells[Vector3i(x, 0, -1)] = true
		wall_cells[Vector3i(x, 0, depth)] = true
	for z in range(-1, depth + 1):
		wall_cells[Vector3i(-1, 0, z)] = true
		wall_cells[Vector3i(width, 0, z)] = true
	for w in blocked:
		wall_cells[w] = true
	var wall_mat := _material(WALL_COLOR)
	for cell in wall_cells:
		dm.add_child(_make_wall_block(dm, dm.cell_to_world(cell), wall_mat))


static func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	return mat


## Dalle mince (sol/plafond) posée sur une case : sa face HAUTE est au niveau `floor_pos`,
## son épaisseur descend en dessous.
static func _make_slab(dm, floor_pos: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(dm.CELL_SIZE, dm.FLOOR_THICKNESS, dm.CELL_SIZE)
	mi.mesh = box
	mi.material_override = mat
	mi.position = floor_pos + Vector3(0.0, -dm.FLOOR_THICKNESS * 0.5, 0.0)
	return mi


## Bloc de mur plein : un cube d'une case, qui remplit le volume de la case au-dessus de son
## sol (donc jamais plus haut qu'un étage — l'étage du dessus reste libre).
##
## `top_mat` non nul = une case de sol repose sur ce mur : on plaque le revêtement de sol sur
## sa face haute (aucune dalle n'est posée par-dessus, c'est le mur qui EST le sol).
static func _make_wall_block(
	dm, floor_pos: Vector3, mat: StandardMaterial3D, top_mat: StandardMaterial3D = null
) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(dm.CELL_SIZE, dm.CELL_SIZE, dm.CELL_SIZE)
	mi.mesh = box
	mi.material_override = mat
	if top_mat != null:
		var skin := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(dm.CELL_SIZE, dm.CELL_SIZE)
		skin.mesh = plane
		skin.material_override = top_mat
		skin.position = Vector3(0.0, dm.CELL_SIZE * 0.5 + 0.002, 0.0)  # juste au-dessus
		mi.add_child(skin)
	mi.position = floor_pos + Vector3(0.0, dm.CELL_SIZE * 0.5, 0.0)
	return mi
