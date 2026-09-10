## Drawing a dungeon: turns the LOGICAL grid into visible meshes.
##
## Kept apart from [DungeonManager], which holds the model — where the floor is, what blocks,
## who occupies what. This script only makes boxes out of it, and reads the dungeon through its
## PUBLIC API alone ([method DungeonManager.floor_tiles], [method DungeonManager.pit_tiles],
## [method DungeonManager.fall_landing]). That is what makes the boundary real: if rendering
## needs a fact, the model has to name it rather than leave it lying around in private.
##
## No `class_name` (the CLI class-cache trap): obtained by `preload`.
extends RefCounted

const FLOOR_COLOR := Color(0.24, 0.24, 0.30)
const PIT_COLOR := Color(0.12, 0.12, 0.16)
const WALL_COLOR := Color(0.14, 0.14, 0.17)


## Lays the visible geometry into `dm`: a one-tile wall block on each of `wall_tiles`, and a
## THIN SLAB ([constant DungeonManager.FLOOR_THICKNESS] thick, doubling as the ceiling of the
## tile below) on each floor tile with NO wall underneath — where there is a wall, its top face
## serves as the floor, per the design doc's "Walls + Decors".
static func render_grid(dm, wall_tiles: Dictionary) -> void:
	var floor_mat := _material(FLOOR_COLOR)
	for c in dm.floor_tiles():
		if dm.pit_tiles().has(c):
			continue  # the lowered slab is rendered further down; the bridge plank goes over it
		if wall_tiles.has(c + Vector3i.DOWN):
			continue  # a wall block serves as the floor, so no slab on top of it
		dm.add_child(_make_slab(dm, dm.tile_to_world(c), floor_mat))

	# Pits get a dark bottom slab below them ONLY when there is no real floor further down —
	# otherwise we would hide the very ravine you are meant to be able to fall into.
	var pit_mat := _material(PIT_COLOR)
	for c in dm.pit_tiles():
		if dm.fall_landing(c) != c:
			continue  # a lower storey already serves as the bottom
		var pos: Vector3 = dm.tile_to_world(c) + Vector3(0.0, -dm.PIT_DEPTH, 0.0)
		dm.add_child(_make_slab(dm, pos, pit_mat))

	var wall_mat := _material(WALL_COLOR)
	for w in wall_tiles:
		# A wall with a floor tile above it wears the floor material on its top face: it IS the
		# floor of the storey above.
		var top_mat: StandardMaterial3D = (
			floor_mat if dm.floor_tiles().has(w + Vector3i.UP) else null
		)
		dm.add_child(_make_wall_block(dm, dm.tile_to_world(w), wall_mat, top_mat))


## Minimal rendering of a demo room: one flat floor in a single piece, plus wall boxes around
## the outside and on the blocked tiles. Scaffolding, like the room itself.
static func build_demo_visuals(dm, width: int, depth: int, blocked: Dictionary) -> void:
	var floor_mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(width * dm.TILE_SIZE, depth * dm.TILE_SIZE)
	floor_mi.mesh = plane
	floor_mi.position = Vector3(
		(width - 1) * dm.TILE_SIZE * 0.5, 0.0, (depth - 1) * dm.TILE_SIZE * 0.5
	)
	dm.add_child(floor_mi)

	var wall_tiles := {}
	for x in range(-1, width + 1):
		wall_tiles[Vector3i(x, 0, -1)] = true
		wall_tiles[Vector3i(x, 0, depth)] = true
	for z in range(-1, depth + 1):
		wall_tiles[Vector3i(-1, 0, z)] = true
		wall_tiles[Vector3i(width, 0, z)] = true
	for w in blocked:
		wall_tiles[w] = true
	var wall_mat := _material(WALL_COLOR)
	for tile in wall_tiles:
		dm.add_child(_make_wall_block(dm, dm.tile_to_world(tile), wall_mat))


static func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	return mat


## A thin floor/ceiling slab on a tile: its TOP face is at `floor_pos`, and its thickness hangs
## below that.
static func _make_slab(dm, floor_pos: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(dm.TILE_SIZE, dm.FLOOR_THICKNESS, dm.TILE_SIZE)
	mi.mesh = box
	mi.material_override = mat
	mi.position = floor_pos + Vector3(0.0, -dm.FLOOR_THICKNESS * 0.5, 0.0)
	return mi


## A solid wall block: a one-tile cube filling the tile's volume above its floor, and so never
## more than one storey tall — the storey above stays free.
##
## A non-null `top_mat` means a floor tile rests on this wall, so the floor material is laid on
## its top face. No slab goes over it: the wall IS the floor.
static func _make_wall_block(
	dm, floor_pos: Vector3, mat: StandardMaterial3D, top_mat: StandardMaterial3D = null
) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(dm.TILE_SIZE, dm.TILE_SIZE, dm.TILE_SIZE)
	mi.mesh = box
	mi.material_override = mat
	if top_mat != null:
		var skin := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(dm.TILE_SIZE, dm.TILE_SIZE)
		skin.mesh = plane
		skin.material_override = top_mat
		skin.position = Vector3(0.0, dm.TILE_SIZE * 0.5 + 0.002, 0.0)  # just above the top face
		mi.add_child(skin)
	mi.position = floor_pos + Vector3(0.0, dm.TILE_SIZE * 0.5, 0.0)
	return mi
