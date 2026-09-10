## A guardrail, protecting the edge of a storey.
##
## Per the design doc ("Walls + Decors / Guardrails") this is geometrically a gateway that never
## opens: [constant DungeonManager.EDGE_THICKNESS] laid on the EDGE between two tiles rather
## than a whole tile. It stops that edge being crossed — and so stops the fall — for the player
## and for the rivals alike, without costing a tile or getting in the way on either side.
##
## Low ([constant HEIGHT], against 1 m for a wall), so you see over it and it does not cut the
## line of sight. That is what tells it apart from a wall along the edge.
##
## No `class_name` (see dungeon_mechanism.gd): `extends` by path.
extends "res://scripts/exploration/mechanisms/dungeon_mechanism.gd"

## The rail's height in metres: below the duo's eyes
## ([constant DungeonManager.EYE_HEIGHT]).
const HEIGHT := 0.3
## The rail's width: nearly the whole edge, leaving a gap for the posts.
const WIDTH := 0.9

## The edge being protected: the guardrail sits between [member tile] and `tile + edge_dir`.
## Always a unit horizontal direction (±X or ±Z).
@export var edge_dir := Vector3i(0, 0, 1)


## On the edge, not on the tile: both neighbouring tiles stay usable.
func _register() -> void:
	_dungeon.register_edge_mechanism(tile, tile + edge_dir, self)


func _unregister() -> void:
	_dungeon.unregister_edge_mechanism(tile, tile + edge_dir, self)


## A guardrail bars its edge permanently: it never opens.
func blocks_walk() -> bool:
	return true


## Low enough to see — and act — over, unlike a wall or a closed gateway.
func blocks_sight() -> bool:
	return false


## Mini-map colour: the light grey of decor, rather than the orange of mechanisms the player
## interacts with — a guardrail is not something you act on.
func map_color() -> Color:
	return Color(0.55, 0.57, 0.62)


func _spawn_visual() -> void:
	var thin := DungeonManager.EDGE_THICKNESS
	var size := Vector3(WIDTH, HEIGHT, WIDTH)
	if edge_dir.x != 0:
		size.x = thin
	else:
		size.z = thin
	var offset := Vector3(edge_dir.x, 0.0, edge_dir.z) * DungeonManager.TILE_SIZE * 0.5
	_add_marker_box(Color(0.62, 0.64, 0.70), size, offset)
