## A top-down picture of a [DungeonPlan], one [Image] per storey, drawn on the CPU.
##
## No engine font and no node: the labels use a 3x5 bitmap font embedded below, so this runs
## headless and the same plan gives the same bytes every time. The colours follow the designers'
## viewer: walls black, water dark blue, ice teal, ground grey, ghosts for rival spawn points,
## orange bars for gates and bridges, cyan arrows for stairs.
##
## A tile is [member scale] pixels wide. Grid lines every tile and a thicker one every 5, column
## letters and row numbers in the margin (A1 is the top left of the grid, as in the viewer). Zones
## tagged `no_teleport` (magenta), `safe` (green) and `event` / `event_area` (yellow) tint the
## tiles they cover. With `issues`, a tile carrying one gets a red border and badge (orange when
## every issue on it is waived, grey when it is only a warning).
##
## No `class_name` (the CLI class-cache trap): referenced by `preload`.
extends RefCounted

const View := preload("res://scripts/dungeon/dungeon_view.gd")

const DEFAULT_SCALE := 24

const WALL := Color8(0, 0, 0)
const WATER := Color8(46, 68, 102)
const ICE := Color8(88, 160, 160)
const GROUND := Color8(64, 64, 64)
const PIT := Color8(26, 26, 36)
const HOLE := Color8(20, 0, 30)
const EMPTY := Color8(255, 255, 255)
const INK := Color8(40, 40, 40)

const ORANGE := Color8(238, 140, 50)
const CYAN := Color8(0, 215, 225)
const GREEN := Color8(40, 220, 70)
const ENTRANCE := Color8(70, 150, 255)
const RED := Color8(230, 30, 30)
const AMBER := Color8(255, 150, 0)
const GREY := Color8(150, 150, 150)

## Zone tag -> tint.
const ZONE_TINTS := {
	"no_teleport": Color(0.85, 0.2, 0.9, 0.38),
	"safe": Color(0.3, 0.9, 0.3, 0.34),
	"event": Color(1.0, 0.85, 0.1, 0.34),
	"event_area": Color(1.0, 0.85, 0.1, 0.34),
}

const GATE_COLORS := {
	"automated": ORANGE,
	"locked": Color8(215, 50, 50),
	"meditation": Color8(165, 95, 225),
	"teleport": Color8(235, 60, 235),
}

## The 3x5 font: five rows of three, `#` for ink. Letters, digits and what a label needs.
const FONT := {
	"A": ".#.#.#####.##.#",
	"B": "##.#.###.#.###.",
	"C": ".###..#..#...##",
	"D": "##.#.##.##.###.",
	"E": "####..##.#..###",
	"F": "####..##.#..#..",
	"G": ".###..#.##.#.##",
	"H": "#.##.#####.##.#",
	"I": "###.#..#..#.###",
	"J": "..#..#..##.#.#.",
	"K": "#.##.###.#.##.#",
	"L": "#..#..#..#..###",
	"M": "#.########.##.#",
	"N": "##.#.##.##.##.#",
	"O": ".#.#.##.##.#.#.",
	"P": "##.#.###.#..#..",
	"Q": ".#.#.##.###..##",
	"R": "##.#.###.#.##.#",
	"S": ".###...#...###.",
	"T": "###.#..#..#..#.",
	"U": "#.##.##.##.####",
	"V": "#.##.##.##.#.#.",
	"W": "#.##.########.#",
	"X": "#.##.#.#.#.##.#",
	"Y": "#.##.#.#..#..#.",
	"Z": "###..#.#.#..###",
	"0": "####.##.##.####",
	"1": ".#.##..#..#.###",
	"2": "###..#####..###",
	"3": "###..####..####",
	"4": "#.##.####..#..#",
	"5": "####..###..####",
	"6": "####..####.####",
	"7": "###..#.#..#..#.",
	"8": "####.#####.####",
	"9": "####.####..####",
	"-": "......###......",
	"_": "............###",
	"!": ".#..#..#.....#.",
	":": "....#.....#....",
	" ": "...............",
}


## The storey `y` of `plan` as an image. Options: `scale` (pixels per tile), `issues` (the
## validator's issues, or absent), `extent` (the tiles to draw, as a Rect2i; the whole dungeon's by
## default, so that every storey has the same size and the same cell names).
static func render_floor(plan, y: int, options: Dictionary = {}) -> Image:
	var s: int = options.get("scale", DEFAULT_SCALE)
	var extent: Rect2i = options.get("extent", View.bounds(plan))
	var issues = options.get("issues", null)
	var marks: Dictionary = View.issue_tiles(issues) if issues != null else {}
	var lay := layout(extent, s)
	var img := Image.create_empty(lay["width"], lay["height"], false, Image.FORMAT_RGBA8)
	img.fill(EMPTY)
	var fs: int = lay["fs"]
	_text(img, lay["left"], fs * 2, "%s FLOOR %d" % [String(plan.slug).to_upper(), y], fs, INK)
	_terrain(plan, img, y, extent, s, lay)
	_zones(plan, img, y, extent, s, lay)
	_grid(img, extent, s, lay)
	_placements(plan, img, y, extent, s, lay)
	_entrance_and_exits(plan, img, y, extent, s, lay)
	for tile in marks:
		if tile.y == y and extent.has_point(Vector2i(tile.x, tile.z)):
			_issue_marker(img, tile_origin(extent, s, tile.x, tile.z), s, marks[tile])
	_labels(img, extent, s, lay)
	return img


## Where everything sits in an image of `extent` at `s` pixels per tile: the font scale `fs`, the
## margins, and the size.
static func layout(extent: Rect2i, s: int) -> Dictionary:
	var fs := maxi(1, s / 12)
	var digits := str(extent.end.y).length()
	var left := digits * 4 * fs + 3 * fs
	var top := 8 * fs + 8 * fs
	return {
		"fs": fs,
		"left": left,
		"top": top,
		"width": left + extent.size.x * s + 3 * fs,
		"height": top + extent.size.y * s + 3 * fs,
	}


## The pixel of the top-left corner of tile (x, z).
static func tile_origin(extent: Rect2i, s: int, x: int, z: int) -> Vector2i:
	var lay := layout(extent, s)
	return Vector2i(
		lay["left"] + (x - extent.position.x) * s, lay["top"] + (z - extent.position.y) * s
	)


## Every storey side by side, lowest on the left. `images` is storey -> [Image].
static func contact_sheet(images: Dictionary) -> Image:
	var ys: Array = images.keys()
	ys.sort()
	var gap := 12
	var width := gap
	var height := 0
	for y in ys:
		width += images[y].get_width() + gap
		height = maxi(height, images[y].get_height())
	var sheet := Image.create_empty(maxi(width, 1), height + 2 * gap, false, Image.FORMAT_RGBA8)
	sheet.fill(Color8(225, 225, 225))
	var x := gap
	for y in ys:
		var img: Image = images[y]
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(x, gap))
		x += img.get_width() + gap
	return sheet


# --------------------------------------------------------------------------
# Layers
# --------------------------------------------------------------------------


static func _terrain(plan, img: Image, y: int, extent: Rect2i, s: int, _lay: Dictionary) -> void:
	for z in range(extent.position.y, extent.end.y):
		for x in range(extent.position.x, extent.end.x):
			var tile := Vector3i(x, y, z)
			var color := EMPTY
			match View.terrain(plan, tile):
				&"floor":
					color = PIT if plan.pit_tiles.has(tile) else GROUND
				&"ice":
					color = ICE
				&"water":
					color = WATER
				&"wall":
					color = WALL
				&"hole":
					color = HOLE
			if color != EMPTY:
				var o := tile_origin(extent, s, x, z)
				img.fill_rect(Rect2i(o.x, o.y, s, s), color)
				if color == HOLE:
					_icon(img, o, s, "cross", Color8(120, 40, 140), Color8(0, 0, 0), Vector3i.ZERO)


static func _zones(plan, img: Image, y: int, extent: Rect2i, s: int, _lay: Dictionary) -> void:
	for name in plan.zones:
		var zone: Dictionary = plan.zones[name]
		for tag in zone["tags"]:
			if not ZONE_TINTS.has(tag):
				continue
			for tile in zone["tiles"]:
				if tile.y == y and extent.has_point(Vector2i(tile.x, tile.z)):
					var o := tile_origin(extent, s, tile.x, tile.z)
					_blend_rect(img, Rect2i(o.x, o.y, s, s), ZONE_TINTS[tag])


static func _grid(img: Image, extent: Rect2i, s: int, lay: Dictionary) -> void:
	var thin := Color(0.5, 0.5, 0.5, 0.4)
	var thick := Color(0.5, 0.5, 0.5, 0.9)
	var w := extent.size.x * s
	var h := extent.size.y * s
	for i in range(extent.size.x + 1):
		var x := extent.position.x + i
		var major := x % 5 == 0
		var rect := Rect2i(
			lay["left"] + i * s - (1 if major else 0), lay["top"], 2 if major else 1, h
		)
		_blend_rect(img, rect, thick if major else thin)
	for j in range(extent.size.y + 1):
		var z := extent.position.y + j
		var major := z % 5 == 0
		var rect := Rect2i(
			lay["left"], lay["top"] + j * s - (1 if major else 0), w, 2 if major else 1
		)
		_blend_rect(img, rect, thick if major else thin)


static func _placements(plan, img: Image, y: int, extent: Rect2i, s: int, _lay: Dictionary) -> void:
	var thick := maxi(3, s / 6)
	for p in plan.placements:
		var tile: Vector3i = p["tile"]
		if tile.y != y or not extent.has_point(Vector2i(tile.x, tile.z)):
			continue
		var o := tile_origin(extent, s, tile.x, tile.z)
		var props: Dictionary = p["props"]
		match p["kind"]:
			&"stairs":
				var face: Vector3i = props.get("face", Vector3i(0, 0, 1))
				_icon(
					img,
					o,
					s,
					"stairs_up" if props.get("dir", "up") == "up" else "stairs_down",
					CYAN,
					INK,
					face
				)
			&"trap":
				match props.get("type", "poison"):
					"disarray":
						_icon(img, o, s, "diamond", Color8(250, 215, 40), INK, Vector3i.ZERO)
					"teleport":
						_icon(img, o, s, "ring", Color8(235, 60, 235), INK, Vector3i.ZERO)
					_:
						_icon(img, o, s, "triangle", Color8(80, 220, 70), INK, Vector3i.ZERO)
			&"chest":
				_icon(
					img,
					o,
					s,
					"chest_trapped" if props.get("trapped", false) else "chest",
					Color8(235, 175, 40),
					INK,
					Vector3i.ZERO
				)
			&"gate":
				var color: Color = GATE_COLORS.get(props.get("type", "automated"), ORANGE)
				_edge_bar(img, o, s, props.get("edge", Vector3i(0, 0, -1)), color, thick)
			&"guardrail":
				_edge_bar(
					img,
					o,
					s,
					props.get("edge", Vector3i(0, 0, -1)),
					Color8(235, 235, 235),
					maxi(2, s / 10)
				)
			&"bridge":
				_bridge_bar(plan, img, o, s, tile)
			&"lift":
				_icon(img, o, s, "lift", Color8(230, 175, 45), INK, Vector3i.ZERO)
			&"crumbly":
				_icon(img, o, s, "crumbly", Color8(160, 110, 70), INK, Vector3i.ZERO)
			&"litter":
				_icon(img, o, s, "litter", Color8(200, 200, 190), INK, Vector3i.ZERO)
			&"crystal":
				_icon(img, o, s, "crystal", Color8(60, 225, 100), INK, Vector3i.ZERO)
			&"dieverting":
				_icon(img, o, s, "cross", Color8(235, 70, 50), INK, Vector3i.ZERO)
			&"cracked_wall":
				_icon(img, o, s, "cracked", Color8(170, 110, 125), INK, Vector3i.ZERO)
			&"rival_spawn":
				_icon(img, o, s, "ghost", Color8(250, 250, 250), INK, Vector3i.ZERO)
			&"special_spawn":
				_icon(img, o, s, "ghost", Color8(255, 110, 110), INK, Vector3i.ZERO)
			&"decor":
				_icon(img, o, s, "orb", Color8(185, 185, 185), Color8(235, 235, 235), Vector3i.ZERO)
			&"scenery":
				_icon(img, o, s, "frame", Color8(240, 240, 240), INK, Vector3i.ZERO)
			_:
				_icon(img, o, s, "frame", Color8(255, 0, 255), INK, Vector3i.ZERO)


static func _entrance_and_exits(
	plan, img: Image, y: int, extent: Rect2i, s: int, lay: Dictionary
) -> void:
	var places: Array = []
	for tile in plan.exits:
		places.append([tile, GREEN, "X"])
	if plan.has_entrance:
		places.append([plan.entrance, ENTRANCE, "E"])
	var thick := maxi(4, s / 5)
	for place in places:
		var tile: Vector3i = place[0]
		if tile.y != y or not extent.has_point(Vector2i(tile.x, tile.z)):
			continue
		var o := tile_origin(extent, s, tile.x, tile.z)
		var edge = plan.tile_props.get(tile, {}).get("exit_edge", null)
		if edge != null:
			_edge_bar(img, o, s, edge, place[1], thick, 0.0)
		else:
			_outline(img, Rect2i(o.x, o.y, s, s), place[1], 2)
		var fs: int = maxi(1, lay["fs"] - 1) if s < 20 else lay["fs"]
		var at := o + Vector2i((s - 3 * fs) / 2, (s - 5 * fs) / 2)
		_text(img, at.x + 1, at.y + 1, place[2], fs, Color8(0, 0, 0))
		_text(img, at.x, at.y, place[2], fs, Color8(255, 255, 255))


static func _issue_marker(img: Image, o: Vector2i, s: int, state: String) -> void:
	var color := RED
	if state == "waived":
		color = AMBER
	elif state == "warning":
		color = GREY
	_outline(img, Rect2i(o.x, o.y, s, s), color, 2)
	var r := maxi(4, s / 5)
	var c := o + Vector2i(s / 4, s / 4)
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy <= r * r:
				_blend(img, c.x + dx, c.y + dy, color)
	_text(img, c.x - 1, c.y - 2, "!", 1, Color8(255, 255, 255))


static func _labels(img: Image, extent: Rect2i, s: int, lay: Dictionary) -> void:
	var fs: int = lay["fs"]
	var longest := View.column_name(extent.end.x - 1).length()
	var step_x := maxi(1, ceili(float(longest * 4 * fs + fs) / float(s)))
	var step_z := maxi(1, ceili(float(6 * fs) / float(s)))
	for x in range(extent.position.x, extent.end.x):
		if (x - extent.position.x) % step_x != 0:
			continue
		var name := View.column_name(x)
		var width := name.length() * 4 * fs - fs
		var o := tile_origin(extent, s, x, extent.position.y)
		_text(img, o.x + (s - width) / 2, lay["top"] - 6 * fs, name, fs, INK)
	for z in range(extent.position.y, extent.end.y):
		if (z - extent.position.y) % step_z != 0:
			continue
		var label := str(z + 1)
		var o := tile_origin(extent, s, extent.position.x, z)
		_text(
			img,
			o.x - 2 * fs - (label.length() * 4 * fs - fs),
			o.y + (s - 5 * fs) / 2,
			label,
			fs,
			INK
		)


# --------------------------------------------------------------------------
# Marks
# --------------------------------------------------------------------------


## A bar on the edge of the tile that `dir` points to, centred on the border line so that it reads
## as lying between two tiles. `inset` shortens it at both ends, as a fraction of the tile.
static func _edge_bar(
	img: Image, o: Vector2i, s: int, dir, color: Color, thick: int, inset := 0.12
) -> void:
	var d: Vector3i = dir
	var pad := int(float(s) * inset)
	var rect := Rect2i()
	if d.z != 0:
		var y := o.y if d.z < 0 else o.y + s
		rect = Rect2i(o.x + pad, y - thick / 2, s - 2 * pad, thick)
	else:
		var x := o.x if d.x < 0 else o.x + s
		rect = Rect2i(x - thick / 2, o.y + pad, thick, s - 2 * pad)
	_blend_rect(img, rect, color)


## A plank: a bar through the middle of the tile, along the way the bridge runs (east-west when
## floor lies east or west of it and not north or south, as in the loader).
static func _bridge_bar(plan, img: Image, o: Vector2i, s: int, tile: Vector3i) -> void:
	var ew: bool = (
		plan.is_floor(tile + Vector3i(1, 0, 0)) or plan.is_floor(tile + Vector3i(-1, 0, 0))
	)
	var ns: bool = (
		plan.is_floor(tile + Vector3i(0, 0, 1)) or plan.is_floor(tile + Vector3i(0, 0, -1))
	)
	var thick := maxi(4, s * 3 / 10)
	if ew and not ns:
		img.fill_rect(Rect2i(o.x, o.y + (s - thick) / 2, s, thick), ORANGE)
	else:
		img.fill_rect(Rect2i(o.x + (s - thick) / 2, o.y, thick, s), ORANGE)


## Paints `shape` in the tile at `o`: `color` for its body, `ink` for details. `face` orients the
## stairs.
static func _icon(
	img: Image, o: Vector2i, s: int, shape: String, color: Color, ink: Color, face: Vector3i
) -> void:
	for py in s:
		for px in s:
			var u := (float(px) + 0.5) / float(s) - 0.5
			var v := (float(py) + 0.5) / float(s) - 0.5
			match _inside(shape, u, v, face):
				1:
					_blend(img, o.x + px, o.y + py, color)
				2:
					_blend(img, o.x + px, o.y + py, ink)
				3:
					_blend(img, o.x + px, o.y + py, RED)


## 0 outside, 1 body, 2 detail, 3 alarm, for the point (u, v) of a tile, each in -0.5 .. 0.5.
static func _inside(shape: String, u: float, v: float, face: Vector3i) -> int:
	var au := absf(u)
	var av := absf(v)
	match shape:
		"diamond":
			return 1 if au + av <= 0.34 else 0
		"ring":
			var r := sqrt(u * u + v * v)
			return 1 if (r >= 0.17 and r <= 0.32) or r <= 0.06 else 0
		"triangle":
			return 1 if v >= -0.3 and v <= 0.28 and au <= 0.36 * (v + 0.3) / 0.58 else 0
		"chest", "chest_trapped":
			if (
				shape == "chest_trapped"
				and u > 0.2
				and v < -0.08
				and (u - 0.3) * (u - 0.3) + (v + 0.18) * (v + 0.18) <= 0.012
			):
				return 3
			if au <= 0.3 and v >= -0.18 and v <= 0.2:
				return 2 if absf(v + 0.02) <= 0.025 else 1
			return 0
		"ghost":
			if (au - 0.1) * (au - 0.1) + (v + 0.1) * (v + 0.1) <= 0.0045:
				return 2
			var inside_head := u * u + (v + 0.08) * (v + 0.08) <= 0.0676
			var inside_body := au <= 0.26 and v >= -0.08 and v <= 0.28
			return 1 if inside_head or inside_body else 0
		"lift":
			var ring := au <= 0.3 and av <= 0.3 and not (au <= 0.22 and av <= 0.22)
			return 1 if ring or (au <= 0.05 and av <= 0.18) else 0
		"crumbly":
			for c in [Vector2(-0.15, -0.1), Vector2(0.12, 0.0), Vector2(-0.02, 0.2)]:
				if absf(u - c.x) <= 0.07 and absf(v - c.y) <= 0.07:
					return 1
			return 0
		"litter":
			for c in [Vector2(-0.15, 0.1), Vector2(0.1, -0.1), Vector2(0.12, 0.15)]:
				if (u - c.x) * (u - c.x) + (v - c.y) * (v - c.y) <= 0.0049:
					return 1
			return 0
		"crystal":
			return 1 if au * 1.7 + av <= 0.38 else 0
		"cross":
			return 1 if absf(au - av) <= 0.07 and au <= 0.32 else 0
		"cracked":
			return 1 if int(floorf((u + v + 1.0) * 5.0)) % 2 == 0 else 0
		"orb":
			var r2 := u * u + v * v
			if r2 <= 0.012:
				return 2
			return 1 if r2 <= 0.05 else 0
		"frame":
			return 1 if au <= 0.3 and av <= 0.3 and not (au <= 0.24 and av <= 0.24) else 0
		"stairs_up", "stairs_down":
			var along := u * face.x + v * face.z
			var across := absf(u * face.z - v * face.x)
			var limit := 0.4 * (0.4 - along) / 0.7
			if along < -0.3 or along > 0.4 or across > limit:
				return 0
			if shape == "stairs_up":
				return 1
			var hollow := (
				along > -0.2 and along < 0.28 and across <= 0.4 * (0.4 - along) / 0.7 - 0.09
			)
			return 0 if hollow else 1
	return 0


# --------------------------------------------------------------------------
# Pixels
# --------------------------------------------------------------------------


static func _blend(img: Image, x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	if c.a >= 1.0:
		img.set_pixel(x, y, c)
		return
	var under := img.get_pixel(x, y)
	img.set_pixel(x, y, under.lerp(Color(c.r, c.g, c.b, 1.0), c.a))


static func _blend_rect(img: Image, rect: Rect2i, c: Color) -> void:
	if c.a >= 1.0:
		img.fill_rect(rect, c)
		return
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			_blend(img, x, y, c)


static func _outline(img: Image, rect: Rect2i, c: Color, w: int) -> void:
	img.fill_rect(Rect2i(rect.position.x, rect.position.y, rect.size.x, w), c)
	img.fill_rect(Rect2i(rect.position.x, rect.end.y - w, rect.size.x, w), c)
	img.fill_rect(Rect2i(rect.position.x, rect.position.y, w, rect.size.y), c)
	img.fill_rect(Rect2i(rect.end.x - w, rect.position.y, w, rect.size.y), c)


## Draws `text` with its top-left corner at (x, y); each font pixel is `fs` x `fs`.
static func _text(img: Image, x: int, y: int, text: String, fs: int, color: Color) -> void:
	var cursor := x
	for ch in text:
		var rows: String = FONT.get(ch, "")
		if rows != "":
			for i in 15:
				if rows[i] == "#":
					img.fill_rect(Rect2i(cursor + (i % 3) * fs, y + (i / 3) * fs, fs, fs), color)
		cursor += 4 * fs
