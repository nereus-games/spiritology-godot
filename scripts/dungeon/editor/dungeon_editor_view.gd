## The map of the dungeon editor: a top-down view of one floor, drawn with `_draw` and nothing
## else. No node per tile — only the tiles on screen are looked at, so a dungeon with no size limit
## costs what the window shows.
##
## It draws the way the designers' viewer does, so that it feels familiar: walls black, water dark
## blue, ice teal, ground grey, stairs cyan with an arrow, orange bars for gates and bridges,
## green for the entrance and the edge an exit is left across. On top: the floor below dimmed,
## the zones, the issues' markers, a highlighted tile, and the cell rulers of a spreadsheet.
##
## It edits nothing. The mouse becomes signals (`stroke_began`, `stroke_moved`, `stroke_ended`,
## `secondary`, `hovered`) that the screen turns into model operations. Wheel zooms around the
## cursor; middle button, or space and left button, pans.
##
## No `class_name` (the CLI class-cache trap): referenced by `preload`.
extends Control

signal stroke_began(tile: Vector3i, shift: bool)
signal stroke_moved(tile: Vector3i)
signal stroke_ended(tile: Vector3i)
signal secondary(tile: Vector3i)
signal hovered(tile: Vector3i, inside: bool)

const Kinds := preload("res://scripts/dungeon/dungeon_kinds.gd")
const Writer := preload("res://scripts/dungeon/dungeon_map_writer.gd")

const MIN_ZOOM := 3.0
const MAX_ZOOM := 96.0
const RULER := 18.0

const FLOOR_COLOR := Color(0.62, 0.62, 0.64)
const ICE_COLOR := Color(0.42, 0.78, 0.80)
const WATER_COLOR := Color(0.10, 0.20, 0.46)
const WALL_COLOR := Color(0.03, 0.03, 0.04)
const HOLE_COLOR := Color(0.0, 0.0, 0.0)
const EMPTY_COLOR := Color(0.17, 0.17, 0.20)
const BACKGROUND := Color(0.09, 0.09, 0.11)
const STAIRS_COLOR := Color(0.15, 0.80, 0.92)
const ORANGE := Color(0.96, 0.58, 0.12)
const GREEN := Color(0.18, 0.82, 0.32)

## Colour and letter of each kind of placement. A kind not in here (a new one in the table) gets a
## colour from its name and its first letter, so it shows up without anyone touching this file.
const KIND_STYLE := {
	&"trap": [Color(0.88, 0.20, 0.20), "!"],
	&"chest": [Color(0.70, 0.46, 0.18), "C"],
	&"lift": [Color(0.62, 0.36, 0.86), "L"],
	&"crumbly": [Color(0.55, 0.42, 0.32), "c"],
	&"litter": [Color(0.50, 0.55, 0.40), "l"],
	&"crystal": [Color(0.80, 0.50, 0.95), "*"],
	&"dieverting": [Color(0.90, 0.80, 0.25), "D"],
	&"rival_spawn": [Color(0.85, 0.30, 0.45), "R"],
	&"special_spawn": [Color(0.95, 0.45, 0.15), "S"],
	&"scenery": [Color(0.40, 0.45, 0.50), "s"],
	&"decor": [Color(0.45, 0.40, 0.55), "d"],
}

var model
var floor_y := 0
var zoom := 18.0
var origin := Vector2(RULER + 8.0, RULER + 8.0)
var show_below := true
var show_zones := true
var show_grid := true
var show_issues := true
var picking := false
## The tile under the mouse, valid when `has_hover`.
var hover_tile := Vector3i.ZERO
var has_hover := false
var selected_tile := Vector3i.ZERO
var has_selection := false
var selected_uid := -1
## A tile to draw attention to (the issue that was clicked).
var highlight_tile := Vector3i.ZERO
var has_highlight := false
var zone_name := ""
## The rectangle being dragged out, or null.
var rect_from = null
var rect_to = null

var _issue_marks: Dictionary = {}  # Vector3i -> "error" | "warning" | "waived"
var _pan_from = null
var _stroking := false
var _last_tile := Vector3i(-1048576, 0, 0)


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE


## Wires the view to a model; it redraws whenever the model changes.
func bind(new_model) -> void:
	model = new_model
	model.changed.connect(queue_redraw)
	queue_redraw()


## `issues` as the validator returns them; the view marks the worst on each tile.
func set_issues(issues: Array) -> void:
	_issue_marks.clear()
	for issue in issues:
		if issue["tile"] == null:
			continue
		var mark := "waived" if issue.has("waived") else String(issue["severity"])
		var old: String = _issue_marks.get(issue["tile"], "")
		if old == "" or _rank(mark) > _rank(old):
			_issue_marks[issue["tile"]] = mark
	queue_redraw()


func clear_issues() -> void:
	_issue_marks.clear()
	queue_redraw()


static func _rank(mark: String) -> int:
	return {"error": 3, "warning": 2, "waived": 1}.get(mark, 0)


# --------------------------------------------------------------------------
# Geometry
# --------------------------------------------------------------------------


func tile_at(pos: Vector2) -> Vector3i:
	var w := (pos - origin) / zoom
	return Vector3i(floori(w.x), floor_y, floori(w.y))


## The top-left corner of a tile on screen.
func tile_to_screen(tile: Vector3i) -> Vector2:
	return origin + Vector2(tile.x, tile.z) * zoom


func tile_center(tile: Vector3i) -> Vector2:
	return tile_to_screen(tile) + Vector2(zoom, zoom) * 0.5


## The tiles on screen, as columns and rows [x0, x1] and [z0, z1] (inclusive, from 0).
func visible_range() -> Rect2i:
	var a := (Vector2.ZERO - origin) / zoom
	var b := (size - origin) / zoom
	var x0 := maxi(0, floori(a.x))
	var z0 := maxi(0, floori(a.y))
	return Rect2i(x0, z0, maxi(0, floori(b.x) - x0 + 1), maxi(0, floori(b.y) - z0 + 1))


## Zooms and pans so that the whole map is in view.
func fit() -> void:
	if model == null or size.x < 10.0:
		return
	var extent: Vector2i = model.extent()
	var room := size - Vector2(RULER * 2.0, RULER * 2.0)
	zoom = clampf(minf(room.x / extent.x, room.y / extent.y), MIN_ZOOM, 40.0)
	var used := Vector2(extent) * zoom
	origin = Vector2(RULER, RULER) + (room - used) * 0.5
	queue_redraw()


## Puts `tile` in the middle of the view (zooming in if the map is tiny on screen).
func center_on(tile: Vector3i) -> void:
	zoom = maxf(zoom, 16.0)
	origin = size * 0.5 - (Vector2(tile.x, tile.z) + Vector2(0.5, 0.5)) * zoom
	queue_redraw()


func zoom_at(pos: Vector2, factor: float) -> void:
	var world := (pos - origin) / zoom
	zoom = clampf(zoom * factor, MIN_ZOOM, MAX_ZOOM)
	origin = pos - world * zoom
	queue_redraw()


# --------------------------------------------------------------------------
# Mouse
# --------------------------------------------------------------------------


## The tiles on the straight line from `a` (left out) to `b` (kept), one step at a time.
static func line_tiles(a: Vector3i, b: Vector3i) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var dx := absi(b.x - a.x)
	var dz := absi(b.z - a.z)
	var sx := 1 if b.x > a.x else -1
	var sz := 1 if b.z > a.z else -1
	var err := dx - dz
	var x := a.x
	var z := a.z
	while x != b.x or z != b.z:
		var e2 := 2 * err
		if e2 > -dz:
			err -= dz
			x += sx
		if e2 < dx:
			err += dx
			z += sz
		out.append(Vector3i(x, b.y, z))
	return out


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_on_button(event)
	elif event is InputEventMouseMotion:
		_on_motion(event)


func _on_button(event: InputEventMouseButton) -> void:
	var tile := tile_at(event.position)
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			if event.pressed:
				zoom_at(event.position, 1.15)
		MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				zoom_at(event.position, 1.0 / 1.15)
		MOUSE_BUTTON_MIDDLE:
			_pan_from = event.position if event.pressed else null
		MOUSE_BUTTON_RIGHT:
			if event.pressed:
				secondary.emit(tile)
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				if Input.is_key_pressed(KEY_SPACE):
					_pan_from = event.position
				else:
					_stroking = true
					_last_tile = tile
					stroke_began.emit(tile, event.shift_pressed)
			else:
				_pan_from = null
				if _stroking:
					_stroking = false
					stroke_ended.emit(tile)


func _on_motion(event: InputEventMouseMotion) -> void:
	if _pan_from != null:
		origin += event.position - _pan_from
		_pan_from = event.position
		queue_redraw()
		return
	var tile := tile_at(event.position)
	var inside: bool = tile.x >= 0 and tile.z >= 0
	if not has_hover or tile != hover_tile:
		hover_tile = tile
		has_hover = true
		hovered.emit(tile, inside)
		queue_redraw()
	if _stroking and tile != _last_tile:
		# A fast drag skips tiles: walk the line between the two so a stroke has no gaps.
		for t in line_tiles(_last_tile, tile):
			stroke_moved.emit(t)
		_last_tile = tile


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		has_hover = false
		hovered.emit(hover_tile, false)
		queue_redraw()
	elif what == NOTIFICATION_RESIZED:
		queue_redraw()


# --------------------------------------------------------------------------
# Drawing
# --------------------------------------------------------------------------


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND)
	if model == null:
		return
	var plan = model.plan
	var view := visible_range()
	var extent: Vector2i = model.extent()
	# The map's own area, a little lighter than the void around it.
	draw_rect(Rect2(origin, Vector2(extent) * zoom), EMPTY_COLOR)
	if show_below:
		_draw_below(view)
	_draw_terrain(view)
	if show_grid and zoom >= 10.0:
		_draw_grid(view, extent)
	if show_zones:
		_draw_zones(plan)
	_draw_tile_marks(plan)
	_draw_placements(plan)
	_draw_entrance_and_exits(plan)
	_draw_emerge()
	if show_issues:
		_draw_issues()
	_draw_overlays()
	_draw_rulers(view)


func _tile_rect(tile: Vector3i) -> Rect2:
	return Rect2(tile_to_screen(tile), Vector2(zoom, zoom))


func _terrain_color(terrain: StringName) -> Color:
	match terrain:
		&"floor":
			return FLOOR_COLOR
		&"ice":
			return ICE_COLOR
		&"water":
			return WATER_COLOR
		&"wall":
			return WALL_COLOR
		&"hole":
			return HOLE_COLOR
	return Color(0, 0, 0, 0)


func _draw_below(view: Rect2i) -> void:
	for z in range(view.position.y, view.end.y):
		for x in range(view.position.x, view.end.x):
			var tile := Vector3i(x, floor_y, z)
			if model.terrain_of(tile) != &"empty":
				continue
			var below := Vector3i(x, floor_y - 1, z)
			var terrain: StringName = model.terrain_of(below)
			if terrain == &"empty":
				continue
			var c := _terrain_color(terrain)
			c.a = 0.30
			draw_rect(_tile_rect(tile), c)


func _draw_terrain(view: Rect2i) -> void:
	for z in range(view.position.y, view.end.y):
		for x in range(view.position.x, view.end.x):
			var tile := Vector3i(x, floor_y, z)
			var terrain: StringName = model.terrain_of(tile)
			if terrain == &"empty":
				continue
			var rect := _tile_rect(tile)
			draw_rect(rect, _terrain_color(terrain))
			if terrain == &"hole" and zoom >= 8.0:
				draw_rect(rect.grow(-zoom * 0.18), Color(0.30, 0.12, 0.10), false, 1.0)


func _draw_grid(view: Rect2i, extent: Vector2i) -> void:
	var color := Color(0, 0, 0, 0.28)
	var x1 := mini(view.end.x, extent.x)
	var z1 := mini(view.end.y, extent.y)
	for x in range(view.position.x, x1 + 1):
		var px := origin.x + x * zoom
		draw_line(
			Vector2(px, origin.y + view.position.y * zoom), Vector2(px, origin.y + z1 * zoom), color
		)
	for z in range(view.position.y, z1 + 1):
		var py := origin.y + z * zoom
		draw_line(
			Vector2(origin.x + view.position.x * zoom, py), Vector2(origin.x + x1 * zoom, py), color
		)


func _draw_zones(plan) -> void:
	var names: Array = plan.zones.keys()
	names.sort()
	for name in names:
		var color := _zone_color(String(name))
		var selected: bool = String(name) == zone_name
		color.a = 0.45 if selected else 0.26
		for tile in plan.zones[name]["tiles"]:
			if tile.y == floor_y:
				draw_rect(_tile_rect(tile), color)
		if selected:
			color.a = 1.0
			for tile in plan.zones[name]["tiles"]:
				if tile.y == floor_y:
					draw_rect(_tile_rect(tile).grow(-1.0), color, false, 1.0)


static func _zone_color(name: String) -> Color:
	return Color.from_hsv(fmod(float(name.hash() % 360) / 360.0, 1.0), 0.65, 0.95)


func _draw_tile_marks(plan) -> void:
	if zoom < 8.0:
		return
	var note := Color(1.0, 0.88, 0.2)
	var tag := Color(0.3, 0.6, 1.0)
	for tile in plan.tile_props:
		if tile.y != floor_y:
			continue
		var props: Dictionary = plan.tile_props[tile]
		var rect := _tile_rect(tile)
		var s := maxf(3.0, zoom * 0.22)
		if props.has("note"):
			draw_rect(Rect2(rect.end.x - s, rect.position.y, s, s), note)
		if props.has("tags"):
			draw_rect(Rect2(rect.position.x, rect.position.y, s, s), tag)


func _draw_placements(plan) -> void:
	var view := Rect2(Vector2.ZERO, size).grow(zoom)
	for p in plan.placements:
		var tile: Vector3i = p["tile"]
		if tile.y != floor_y or not view.has_point(tile_center(tile)):
			continue
		_draw_placement(p)
		var props: Dictionary = p["props"]
		if zoom >= 8.0:
			var rect := _tile_rect(tile)
			var s := maxf(3.0, zoom * 0.22)
			if props.has("note"):
				draw_rect(Rect2(rect.end.x - s, rect.position.y, s, s), Color(1.0, 0.88, 0.2))
			if props.has("tags"):
				draw_rect(Rect2(rect.position.x, rect.position.y, s, s), Color(0.3, 0.6, 1.0))
		if p["uid"] == selected_uid:
			draw_rect(_tile_rect(tile).grow(1.0), Color(1, 1, 0.3), false, 2.0)


func _draw_placement(p: Dictionary) -> void:
	var kind: StringName = p["kind"]
	var props: Dictionary = p["props"]
	var rect := _tile_rect(p["tile"])
	var center := rect.get_center()
	match kind:
		&"stairs":
			var up: bool = props.get("dir", "up") == "up"
			draw_rect(rect.grow(-1.0), STAIRS_COLOR if up else STAIRS_COLOR.darkened(0.45))
			if props.has("face"):
				_draw_arrow(center, Vector2(props["face"].x, props["face"].z), zoom * 0.32, up)
			return
		&"gate":
			_draw_edge_bar(rect, props.get("edge"), ORANGE, 0.20)
			if not props.has("edge"):
				draw_rect(rect.grow(-2.0), ORANGE, false, 2.0)
			return
		&"guardrail":
			_draw_edge_bar(rect, props.get("edge"), ORANGE, 0.08)
			return
		&"bridge":
			var plank := ORANGE
			for k in [-0.28, 0.0, 0.28]:
				draw_rect(
					Rect2(
						rect.position.x + zoom * 0.08,
						center.y + zoom * k - zoom * 0.06,
						zoom * 0.84,
						zoom * 0.12
					),
					plank
				)
			return
		&"cracked_wall":
			draw_rect(rect, Color(0.28, 0.28, 0.30))
			var a := rect.position
			draw_polyline(
				PackedVector2Array(
					[
						a + Vector2(0.15, 0.1) * zoom,
						a + Vector2(0.5, 0.4) * zoom,
						a + Vector2(0.35, 0.6) * zoom,
						a + Vector2(0.85, 0.9) * zoom
					]
				),
				Color(0.9, 0.9, 0.9),
				maxf(1.0, zoom * 0.06)
			)
			return
	var style = KIND_STYLE.get(kind)
	var color: Color
	var letter: String
	if style != null:
		color = style[0]
		letter = style[1]
	else:
		color = Color.from_hsv(float(String(kind).hash() % 360) / 360.0, 0.6, 0.85)
		letter = String(kind).substr(0, 1).to_upper()
	var radius := zoom * (0.22 if kind in [&"scenery", &"decor"] else 0.34)
	draw_circle(center, radius, color)
	if zoom >= 12.0 and kind not in [&"scenery", &"decor"]:
		_draw_letter(center, letter, Color.WHITE)


## A bar along the edge of a tile (`edge` a direction vector, N being -z), `thickness` of a tile.
func _draw_edge_bar(rect: Rect2, edge, color: Color, thickness: float) -> void:
	if edge == null:
		return
	var t := maxf(2.0, zoom * thickness)
	if edge.z < 0:
		draw_rect(Rect2(rect.position.x, rect.position.y - t * 0.5, rect.size.x, t), color)
	elif edge.z > 0:
		draw_rect(Rect2(rect.position.x, rect.end.y - t * 0.5, rect.size.x, t), color)
	elif edge.x > 0:
		draw_rect(Rect2(rect.end.x - t * 0.5, rect.position.y, t, rect.size.y), color)
	else:
		draw_rect(Rect2(rect.position.x - t * 0.5, rect.position.y, t, rect.size.y), color)


func _draw_arrow(center: Vector2, dir: Vector2, length: float, filled: bool) -> void:
	var d := dir.normalized()
	var perp := Vector2(-d.y, d.x)
	var tip := center + d * length
	var base := center - d * length * 0.6
	var tri := PackedVector2Array([tip, base + perp * length * 0.8, base - perp * length * 0.8])
	var color := Color.WHITE if filled else Color(0.02, 0.2, 0.3)
	draw_colored_polygon(tri, color)
	draw_line(base, center - d * length, color, maxf(1.0, length * 0.25))


func _draw_letter(center: Vector2, letter: String, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var fs := int(clampf(zoom * 0.5, 8.0, 40.0))
	var width := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
	draw_string(
		font,
		center + Vector2(-width * 0.5, fs * 0.36),
		letter,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		fs,
		color
	)


func _draw_entrance_and_exits(plan) -> void:
	if plan.has_entrance and plan.entrance.y == floor_y:
		var rect := _tile_rect(plan.entrance)
		draw_rect(rect.grow(-1.0), GREEN, false, maxf(2.0, zoom * 0.1))
		var props: Dictionary = plan.tile_props.get(plan.entrance, {})
		if props.has("facing"):
			_draw_arrow(
				rect.get_center(), Vector2(props["facing"].x, props["facing"].z), zoom * 0.28, true
			)
		else:
			_draw_letter(rect.get_center(), "E", GREEN)
		_draw_edge_bar(rect, props.get("exit_edge"), GREEN, 0.14)
	for tile in plan.exits:
		if tile.y != floor_y:
			continue
		var rect := _tile_rect(tile)
		draw_rect(rect.grow(-1.0), GREEN, false, maxf(2.0, zoom * 0.1))
		_draw_letter(rect.get_center(), "X", GREEN)
		_draw_edge_bar(rect, plan.tile_props.get(tile, {}).get("exit_edge"), GREEN, 0.14)


func _draw_emerge() -> void:
	var tile = model.emerge_tile()
	if tile == null or tile.y != floor_y:
		return
	var rect := _tile_rect(tile)
	var c := Color(0.35, 0.65, 1.0)
	draw_rect(rect.grow(-1.0), c, false, 2.0)
	for k in [0.35, 0.6]:
		draw_polyline(
			PackedVector2Array(
				[
					rect.position + Vector2(0.2, k) * zoom,
					rect.position + Vector2(0.4, k - 0.12) * zoom,
					rect.position + Vector2(0.6, k + 0.12) * zoom,
					rect.position + Vector2(0.8, k) * zoom,
				]
			),
			c,
			maxf(1.0, zoom * 0.06)
		)


func _draw_issues() -> void:
	for tile in _issue_marks:
		if tile.y != floor_y:
			continue
		var rect := _tile_rect(tile)
		if not Rect2(Vector2.ZERO, size).intersects(rect):
			continue
		var mark: String = _issue_marks[tile]
		var color := Color(0.95, 0.15, 0.15)
		if mark == "warning":
			color = Color(0.98, 0.85, 0.15)
		elif mark == "waived":
			color = Color(0.65, 0.62, 0.40)
		var r := maxf(3.0, zoom * 0.17)
		var spot := Vector2(rect.position.x + r + 1.0, rect.end.y - r - 1.0)
		draw_circle(spot, r, color)
		draw_arc(spot, r, 0.0, TAU, 12, Color.BLACK, 1.0)
		if mark == "waived":
			draw_line(spot - Vector2(r, 0) * 0.6, spot + Vector2(r, 0) * 0.6, Color.BLACK, 1.0)


func _draw_overlays() -> void:
	if has_highlight and highlight_tile.y == floor_y:
		var rect := _tile_rect(highlight_tile)
		draw_rect(rect.grow(zoom * 0.25), Color(1.0, 0.2, 0.9, 0.25))
		draw_rect(rect.grow(2.0), Color(1.0, 0.2, 0.9), false, 3.0)
	if has_selection and selected_tile.y == floor_y:
		draw_rect(_tile_rect(selected_tile).grow(1.0), Color(0.3, 1.0, 1.0), false, 2.0)
	if rect_from != null and rect_to != null:
		var a: Vector3i = rect_from
		var b: Vector3i = rect_to
		var x0 := mini(a.x, b.x)
		var z0 := mini(a.z, b.z)
		var r := Rect2(
			tile_to_screen(Vector3i(x0, floor_y, z0)),
			Vector2(absi(a.x - b.x) + 1, absi(a.z - b.z) + 1) * zoom
		)
		draw_rect(r, Color(1, 1, 1, 0.18))
		draw_rect(r, Color(1, 1, 1, 0.9), false, 2.0)
	if has_hover:
		var c := Color(1.0, 0.85, 0.2) if picking else Color(1, 1, 1, 0.9)
		draw_rect(_tile_rect(hover_tile), c, false, 2.0)


func _draw_rulers(view: Rect2i) -> void:
	if zoom < 9.0:
		return
	var font := ThemeDB.fallback_font
	var fs := 11
	var every := 1 if zoom >= 18.0 else (2 if zoom >= 12.0 else 5)
	draw_rect(Rect2(0, 0, size.x, RULER), Color(0.05, 0.05, 0.07, 0.88))
	draw_rect(Rect2(0, 0, RULER + 6.0, size.y), Color(0.05, 0.05, 0.07, 0.88))
	for x in range(view.position.x, view.end.x):
		if x % every != 0:
			continue
		var cell := Writer.cell_name(x, 0).rstrip("1")
		var px := origin.x + x * zoom + zoom * 0.5
		draw_string(
			font,
			Vector2(px - 5.0 * cell.length(), RULER - 5.0),
			cell,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			fs,
			Color(0.8, 0.8, 0.85)
		)
	for z in range(view.position.y, view.end.y):
		if z % every != 0:
			continue
		var py := origin.y + z * zoom + zoom * 0.5 + 4.0
		draw_string(
			font,
			Vector2(1.0, py),
			str(z + 1),
			HORIZONTAL_ALIGNMENT_LEFT,
			RULER + 4.0,
			fs,
			Color(0.8, 0.8, 0.85)
		)
