## An ASCII rendering of a [DungeonPlan], to read in a terminal or a pull request.
##
## One block per storey: column letters across the top and row numbers down the side exactly as
## the designers' viewer names them (A..Z, AA..AE; rows from 1), the terrain characters of the
## `.map` format (`.` floor, `i` ice, `~` water, `#` wall, `:` hole, `_` nothing), and every
## placement overlaid as ONE character that means one thing only (see [constant LEGEND]). A tile
## holding several placements shows `*`; `list` spells them out. Zones are a second layer under
## the map, and with `issues` a tile carrying an issue shows `!` and the issues are listed.
##
## Options (all optional): `floor` (int), `zone` (String), `rect` (Rect2i, in tiles), `issues`
## (the validator's issues; their presence turns the layer on), `list` (bool).
##
## Pure functions, no nodes. No `class_name` (the CLI class-cache trap): referenced by `preload`.
extends RefCounted

const Kinds := preload("res://scripts/dungeon/dungeon_kinds.gd")
const View := preload("res://scripts/dungeon/dungeon_view.gd")
const Validator := preload("res://scripts/dungeon/dungeon_validator.gd")

## Every character the dump can draw beyond the terrain, in legend order.
const LEGEND := [
	["E", "entrance"],
	["X", "exit"],
	["^", "stairs up, face N"],
	[">", "stairs up, face E"],
	["v", "stairs up, face S"],
	["<", "stairs up, face W"],
	["n", "stairs down, face N"],
	["e", "stairs down, face E"],
	["z", "stairs down, face S"],
	["w", "stairs down, face W"],
	["D", "disarray trap"],
	["P", "poison trap"],
	["T", "teleport trap"],
	["c", "chest"],
	["C", "trapped chest"],
	["-", "gate on a north or south edge"],
	["|", "gate on an east or west edge"],
	["+", "teleport gate"],
	["=", "guardrail on a north or south edge"],
	["H", "guardrail on an east or west edge"],
	["b", "bridge over a drop"],
	["B", "bridge over water"],
	["L", "lift"],
	["r", "crumbly ground"],
	["%", "litter"],
	["q", "refresh crystal"],
	["Z", "dieverting"],
	["k", "cracked wall"],
	["s", "rival spawn point"],
	["S", "special spawn point"],
	["o", "examinable decor"],
	["$", "scenery"],
	["*", "several placements on one tile (see --list)"],
	["?", "unknown kind"],
	[".", "floor"],
	["i", "ice"],
	["~", "water"],
	["#", "wall"],
	[":", "hole"],
	["_", "nothing"],
	["!", "a tile with an issue (--issues)"],
]

const ZONE_MARKS := "123456789abcdefghijklmnopqrstuvwxyz"


## Why `options` cannot be rendered for `plan`, or "".
static func problem(plan, options: Dictionary) -> String:
	if options.has("floor") and not View.floors(plan).has(int(options["floor"])):
		return "no floor %d in %s" % [int(options["floor"]), plan.slug]
	if options.has("zone") and not plan.zones.has(String(options["zone"])):
		var names: Array = plan.zones.keys()
		names.sort()
		return "no zone '%s' in %s (zones: %s)" % [options["zone"], plan.slug, ", ".join(names)]
	return ""


## The whole dump as text, ending in a newline.
static func render(plan, options: Dictionary = {}) -> String:
	var issues = options.get("issues", null)
	var marks: Dictionary = View.issue_tiles(issues) if issues != null else {}
	var ys: Array[int] = []
	if options.has("floor"):
		ys.append(int(options["floor"]))
	else:
		ys = View.floors(plan)
	var out := "%s: %s\n" % [plan.slug, ", ".join(_floor_names(ys))]
	var used := {}
	var rendered := 0
	for y in ys:
		var view := _view_rect(plan, y, options)
		if view.size == Vector2i.ZERO:
			continue
		rendered += 1
		out += "\n" + _render_floor(plan, y, view, options, marks, used)
		if issues != null:
			out += _issue_lines(issues, y)
	if rendered == 0:
		out += "\n(nothing to show there)\n"
	if issues != null:
		out += _floorless_issue_lines(issues)
	out += "\n" + _legend(used)
	return out


static func _floor_names(ys: Array[int]) -> Array:
	var names: Array = []
	for y in ys:
		names.append("floor %d" % y)
	return names


## The rectangle shown for storey `y`: the `rect` option, else the zone's tiles with one tile
## around them, else the whole storey from A1.
static func _view_rect(plan, y: int, options: Dictionary) -> Rect2i:
	var whole := View.bounds(plan, y)
	if options.has("rect"):
		var r: Rect2i = options["rect"]
		return r if r.intersects(whole) else Rect2i()
	if options.has("zone"):
		var lo := Vector2i(1 << 30, 1 << 30)
		var hi := Vector2i(-(1 << 30), -(1 << 30))
		var any := false
		for tile in plan.zones[String(options["zone"])]["tiles"]:
			if tile.y != y:
				continue
			any = true
			lo = Vector2i(mini(lo.x, tile.x), mini(lo.y, tile.z))
			hi = Vector2i(maxi(hi.x, tile.x), maxi(hi.y, tile.z))
		if not any:
			return Rect2i()
		var padded := Rect2i(lo - Vector2i.ONE, hi - lo + Vector2i(3, 3))
		return padded.intersection(whole)
	return whole


static func _render_floor(
	plan, y: int, view: Rect2i, options: Dictionary, marks: Dictionary, used: Dictionary
) -> String:
	var title := "== floor %d ==  %s:%s" % [y, _name(view.position), _name(view.end - Vector2i.ONE)]
	var zone_filter := String(options.get("zone", ""))
	if zone_filter != "":
		title += "  zone %s" % zone_filter
	var out := title + "\n"
	var row_width := str(view.end.y).length()
	var rows: Array[String] = []
	for z in range(view.position.y, view.end.y):
		var line := ""
		for x in range(view.position.x, view.end.x):
			var tile := Vector3i(x, y, z)
			var ch := "!" if marks.has(tile) else glyph(plan, tile)
			used[ch] = true
			line += ch
		rows.append(line)
	out += _column_header(view, row_width)
	for i in rows.size():
		out += "%*d %s\n" % [row_width, view.position.y + i + 1, rows[i]]
	out += _zone_layer(plan, y, view, row_width)
	if options.get("list", false):
		out += _placement_list(plan, y, view)
	return out


static func _name(cell: Vector2i) -> String:
	return View.cell_name(cell.x, cell.y)


## Two header lines when a column has two letters (the first letter above, the last below), one
## otherwise. Every line is padded to the width of the row labels.
static func _column_header(view: Rect2i, row_width: int) -> String:
	var pad := " ".repeat(row_width + 1)
	var top := ""
	var bottom := ""
	var two := false
	for x in range(view.position.x, view.end.x):
		var name := View.column_name(x)
		if name.length() > 1:
			two = true
			top += name[0]
		else:
			top += " "
		bottom += name[name.length() - 1]
	var out := ""
	if two:
		out += pad + top.rstrip(" ") + "\n"
	return out + pad + bottom + "\n"


## One character for a tile: the entrance, an exit, ONE placement, `*` for several, else terrain.
static func glyph(plan, tile: Vector3i) -> String:
	var found: Array[String] = []
	if plan.has_entrance and plan.entrance == tile:
		found.append("E")
	if plan.exits.has(tile):
		found.append("X")
	for p in plan.placements_at(tile):
		found.append(placement_glyph(p))
	if found.size() > 1:
		return "*"
	if found.size() == 1:
		return found[0]
	match View.terrain(plan, tile):
		&"floor":
			return "."
		&"ice":
			return "i"
		&"water":
			return "~"
		&"wall":
			return "#"
		&"hole":
			return ":"
	return "_"


## The character of one placement (see [constant LEGEND]).
static func placement_glyph(p: Dictionary) -> String:
	var props: Dictionary = p["props"]
	var face: String = View.face_letter(props.get("face", null))
	var edge_ns: bool = props.get("edge", Vector3i.ZERO).x == 0
	match p["kind"]:
		&"stairs":
			var at := "NESW".find(face)
			if at < 0:
				return "?"
			return ("^>v<" if props.get("dir", "up") == "up" else "nezw")[at]
		&"trap":
			return {"disarray": "D", "teleport": "T"}.get(props.get("type", "poison"), "P")
		&"chest":
			return "C" if props.get("trapped", false) else "c"
		&"gate":
			if props.get("type", "automated") == "teleport":
				return "+"
			return "-" if edge_ns else "|"
		&"guardrail":
			return "=" if edge_ns else "H"
		&"bridge":
			return "B" if props.get("over", "void") == "water" else "b"
		&"lift":
			return "L"
		&"crumbly":
			return "r"
		&"litter":
			return "%"
		&"crystal":
			return "q"
		&"dieverting":
			return "Z"
		&"cracked_wall":
			return "k"
		&"rival_spawn":
			return "s"
		&"special_spawn":
			return "S"
		&"decor":
			return "o"
		&"scenery":
			return "$"
	return "?"


# --------------------------------------------------------------------------
# Layers and lists
# --------------------------------------------------------------------------


## The zones of storey `y` inside `view`, each with a mark, drawn on a grid of its own, and a key.
static func _zone_layer(plan, y: int, view: Rect2i, row_width: int) -> String:
	var names: Array = []
	for name in plan.zones:
		for tile in plan.zones[name]["tiles"]:
			if tile.y == y and view.has_point(Vector2i(tile.x, tile.z)):
				names.append(name)
				break
	if names.is_empty():
		return ""
	names.sort()
	var mark_of := {}
	for i in names.size():
		mark_of[names[i]] = ZONE_MARKS[mini(i, ZONE_MARKS.length() - 1)]
	var out := "zones:\n" + _column_header(view, row_width)
	var lines := {}
	var several := false
	for z in range(view.position.y, view.end.y):
		var line := ""
		for x in range(view.position.x, view.end.x):
			var tile := Vector3i(x, y, z)
			var here: Array = []
			for name in names:
				if plan.zones[name]["tiles"].has(tile):
					here.append(name)
			if here.is_empty():
				line += " "
			elif here.size() > 1:
				line += "*"
				several = true
			else:
				line += mark_of[here[0]]
		if line.strip_edges() != "":
			lines[z] = line.rstrip(" ")
	# Only the rows between the first and the last zone tile, so a small zone is a small block.
	var rows: Array = lines.keys()
	for z in range(rows.min(), rows.max() + 1):
		out += "%*d %s\n" % [row_width, z + 1, lines.get(z, "")]
	for name in names:
		var tags: Array = plan.zones[name]["tags"]
		out += "  %s = %s%s\n" % [mark_of[name], name, "  [%s]" % ",".join(tags) if tags else ""]
	if several:
		out += "  * = several zones\n"
	return out


## Every placement of storey `y` inside `view`, one per line, with its properties.
static func _placement_list(plan, y: int, view: Rect2i) -> String:
	var lines: Array[String] = []
	for p in plan.placements:
		var tile: Vector3i = p["tile"]
		if tile.y != y or not view.has_point(Vector2i(tile.x, tile.z)):
			continue
		lines.append(
			(
				"  %-5s %s %s"
				% [View.tile_name(tile), placement_glyph(p), _describe(p["kind"], p["props"])]
			)
		)
	if lines.is_empty():
		return ""
	lines.sort()
	return "placements:\n" + "\n".join(lines) + "\n"


static func _describe(kind: StringName, props: Dictionary) -> String:
	var parts: Array[String] = [String(kind)]
	var keys: Array = props.keys()
	keys.sort()
	for key in keys:
		parts.append("%s=%s" % [key, format_value(props[key])])
	return " ".join(parts)


## A property value the way a map file would write it.
static func format_value(value) -> String:
	if value is Vector3i:
		var d := View.face_letter(value)
		return d if d != "" else View.tile_name(value, true)
	if value is Array:
		var parts: Array[String] = []
		for item in value:
			parts.append(format_value(item))
		return ";".join(parts) if not value.is_empty() and value[0] is Vector3i else ",".join(parts)
	return str(value)


static func _issue_lines(issues: Array, y: int) -> String:
	var lines: Array[String] = []
	for issue in issues:
		if issue["tile"] != null and issue["tile"].y == y:
			lines.append(_issue_line(issue))
	if lines.is_empty():
		return ""
	return "issues:\n" + "\n".join(lines) + "\n"


static func _floorless_issue_lines(issues: Array) -> String:
	var lines: Array[String] = []
	for issue in issues:
		if issue["tile"] == null:
			lines.append(_issue_line(issue))
	if lines.is_empty():
		return ""
	return "\nissues with no tile:\n" + "\n".join(lines) + "\n"


static func _issue_line(issue: Dictionary) -> String:
	var where := "     "
	if issue["tile"] != null:
		where = "%-5s" % View.tile_name(issue["tile"])
	var text := "  %-7s %s %s" % [issue["severity"], where, Validator.message(issue)]
	if issue.has("waived"):
		text += "  [waived: %s]" % issue["waived"]
	return text


static func _legend(used: Dictionary) -> String:
	var out := "legend:\n"
	for entry in LEGEND:
		if used.has(entry[0]):
			out += "  %s  %s\n" % entry
	return out
