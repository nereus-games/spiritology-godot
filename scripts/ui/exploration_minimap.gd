## The exploration mini-map (element 1 of the HUD, per the design doc's "User Interface").
##
## Draws the dungeon's LOGICAL grid from above: floor slabs, mechanisms, and the player's
## position. A test placeholder made of simple shapes, redrawn every frame. Asks the dungeon (the
## "dungeon" group) and the player (the "player" group).
##
## No `class_name` (the CLI class-cache trap): referenced by `preload`.
extends Control

## How big one cell is on the mini-map, in pixels.
const CELL_PX := 11.0

const FLOOR_COLOR := Color(0.30, 0.30, 0.36)
## Cells on a storey BELOW the player's: dimmed, so the edge of the storey you are on — a
## platform's lip, a stairwell — reads at a glance.
const FLOOR_BELOW_COLOR := Color(0.15, 0.15, 0.19)
## Walls on the current storey: darker than the floor but clearly above the background, so a
## room's OUTLINE reads. The design doc has the map show floor and walls.
const WALL_COLOR := Color(0.20, 0.20, 0.25)
const MECH_COLOR := Color(0.90, 0.65, 0.20)
## A SPENT mechanism — a sprung trap, an emptied chest, a rolled die, dug ground. The same rule
## as in 3D: what is no longer actionable must stop drawing the eye like a lead worth following.
## It stays drawn, as a landmark, and because the design doc explicitly asks for an icon on the
## map for crumbly ground already dug — but dulled.
const MECH_SPENT_COLOR := Color(0.38, 0.33, 0.26)
const PLAYER_COLOR := Color(0.40, 0.90, 0.55)
const BG_COLOR := Color(0.05, 0.05, 0.07, 0.6)

var _dungeon
var _player


func _ready() -> void:
	custom_minimum_size = Vector2(170, 170)
	clip_contents = true  # a large dungeon must not spill over the rest of the HUD


func _process(_delta: float) -> void:
	if _dungeon == null:
		_dungeon = get_tree().get_first_node_in_group("dungeon")
	if _player == null:
		_player = get_tree().get_first_node_in_group("player")
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG_COLOR)
	if _dungeon == null:
		return
	var floors: Array = _dungeon._floor.keys()
	if floors.is_empty():
		return
	# Grid bounds over floors AND walls, or the outline would be drawn outside the frame.
	var minx: int = floors[0].x
	var minz: int = floors[0].z
	var maxx: int = minx
	var maxz: int = minz
	for c in floors + _dungeon.wall_cells().keys():
		minx = mini(minx, c.x)
		minz = mini(minz, c.z)
		maxx = maxi(maxx, c.x)
		maxz = maxi(maxz, c.z)
	var grid := Vector2((maxx - minx + 1) * CELL_PX, (maxz - minz + 1) * CELL_PX)
	var origin := (size - grid) * 0.5

	# The player's current storey: what is below is dimmed, what is above is not mapped at all —
	# you do not see through a ceiling.
	var level: int = _player.cell.y if is_instance_valid(_player) else 0
	# Floor slabs: the lower storeys first, the current one over them.
	for c in floors:
		if c.y < level:
			draw_rect(
				Rect2(_cell_px(c, origin, maxx, maxz), Vector2(CELL_PX - 1.0, CELL_PX - 1.0)),
				FLOOR_BELOW_COLOR
			)
	for c in floors:
		if c.y == level:
			draw_rect(
				Rect2(_cell_px(c, origin, maxx, maxz), Vector2(CELL_PX - 1.0, CELL_PX - 1.0)),
				FLOOR_COLOR
			)
	# Walls on the current storey, over the floors: a wall may carry the storey above's floor, and
	# on this storey what you should see is a wall.
	for w in _dungeon.wall_cells():
		if w.y == level:
			draw_rect(
				Rect2(_cell_px(w, origin, maxx, maxz), Vector2(CELL_PX - 1.0, CELL_PX - 1.0)),
				WALL_COLOR
			)
	# Mechanisms on the current storey: on a cell (a solid block) or on the edge between two cells
	# (a thin bar, for the gateways, which occupy no cell).
	for m in get_tree().get_nodes_in_group("dungeon_mechanism"):
		if not is_instance_valid(m) or m.cell.y != level or not m.shows_on_map():
			continue  # an unknown trap does not give itself away on the map
		# A mechanism may impose its own hue — a guardrail uses the grey of decor, since you never
		# act on it. Otherwise the orange of interactive mechanisms, dulled once spent.
		var color: Color = MECH_SPENT_COLOR if m.is_spent() else MECH_COLOR
		if m.has_method("map_color"):
			color = m.map_color()
		var edge = m.get("edge_dir")
		if edge != null:
			_draw_edge_mech(m.cell, edge, origin, maxx, maxz, color)
		else:
			draw_rect(
				Rect2(_cell_px(m.cell, origin, maxx, maxz), Vector2(CELL_PX - 1.0, CELL_PX - 1.0)),
				color
			)
	# The player, as an arrow pointing the way they face.
	if is_instance_valid(_player):
		var p := _cell_px(_player.cell, origin, maxx, maxz) + Vector2(CELL_PX, CELL_PX) * 0.5
		_draw_player_arrow(p)


## Cell to pixel. The map is turned 180 degrees — both axes inverted — so the starting position is
## at the BOTTOM and the front of the dungeon (+z) points UP, with left and right matching how you
## move.
func _cell_px(c: Vector3i, origin: Vector2, maxx: int, maxz: int) -> Vector2:
	return origin + Vector2((maxx - c.x) * CELL_PX, (maxz - c.z) * CELL_PX)


## An edge mechanism (a gateway): a thin bar on the boundary between `cell` and
## `cell + edge_dir`, laid on the side matching the map's inverted axes.
func _draw_edge_mech(
	cell: Vector3i, edge_dir: Vector3i, origin: Vector2, maxx: int, maxz: int, color: Color
) -> void:
	const THICK := 2.0
	var p := _cell_px(cell, origin, maxx, maxz)
	# The map inverts both axes, so the +x/+z neighbour is at -px on it.
	if edge_dir.x != 0:
		var x := p.x + (0.0 if edge_dir.x > 0 else CELL_PX - THICK)
		draw_rect(Rect2(Vector2(x, p.y), Vector2(THICK, CELL_PX - 1.0)), color)
	else:
		var y := p.y + (0.0 if edge_dir.z > 0 else CELL_PX - THICK)
		draw_rect(Rect2(Vector2(p.x, y), Vector2(CELL_PX - 1.0, THICK)), color)


## A small triangle pointing along the player's MOVEMENT direction — cardinal, a multiple of 90
## degrees — rather than free look, so it predicts where a step would actually go.
func _draw_player_arrow(center: Vector2) -> void:
	var dir := Vector2(0.0, -1.0)  # default: upwards
	if _player.has_method("facing_delta"):
		var fd: Vector3i = _player.facing_delta()  # a cardinal cell delta
		var d := Vector2(-fd.x, -fd.z)  # the same axis inversion as the map
		if d.length() > 0.01:
			dir = d.normalized()
	var perp := Vector2(-dir.y, dir.x)
	var r := CELL_PX * 0.6
	var pts := PackedVector2Array(
		[
			center + dir * r,
			center - dir * r * 0.7 + perp * r * 0.6,
			center - dir * r * 0.7 - perp * r * 0.6,
		]
	)
	draw_colored_polygon(pts, PLAYER_COLOR)
