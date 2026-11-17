## Writes a [DungeonPlan] back to its map files: the inverse of [DungeonMapParser], and in the
## same canonical layout as `tools/import_mapper.py` (its `write_floors`), so that a file the
## importer wrote, the editor loaded and the editor saved again differs only where something was
## actually edited.
##
## Pure functions, no nodes. The two guarantees, both checked by `dungeon_editor_check`:
##
## - the text parses back to the same plan (tiles, placements and their properties, zones, tile
##   properties), and
## - the text is a fixed point: `write(parse(write(plan))) == write(plan)`.
##
## What a file can carry that a plan cannot: comments. The writer regenerates the header and the
## `# group` headings and drops any other comment, so what a designer wants to keep belongs in a
## `note=`.
##
## The layout of a storey: header comments, `[floor]`, `[grid]` (every storey as wide and as deep
## as the largest, or as `opts["size"]` says), `[legend]` (stairs only, `^ > v <` climb north, east,
## south, west and `n e s w` descend), `[tiles]` (one tile per line, named by cell, under a
## `# group` heading, sorted by group then row then column) and `[zones]`.
##
## No `class_name` (the CLI class-cache trap): referenced by `preload`.
extends RefCounted

const Kinds := preload("res://scripts/dungeon/dungeon_kinds.gd")

const UP_CHAR := {"N": "^", "E": ">", "S": "v", "W": "<"}
const DOWN_CHAR := {"N": "n", "E": "e", "S": "s", "W": "w"}
const DEFAULT_NOTE_LINE := "# Written by the dungeon editor; edit freely, saving rewrites this layout."
## The order the common properties are written in, after the kind's own.
const COMMON_ORDER: Array[String] = ["exit_edge", "facing", "tags", "asset", "note"]
## A zone's pieces: how many lone tiles go on one line.
const SINGLES_PER_LINE := 8


## `floor_<y>.map`.
static func file_name(y: int) -> String:
	return "floor_%d.map" % y


## The storeys a plan has anything on, lowest first.
static func floors_of(plan) -> Array[int]:
	var seen := {}
	for dict in [
		plan.floor_tiles, plan.hole_tiles, plan.pit_tiles, plan.wall_tiles, plan.water_tiles,
		plan.tile_props
	]:
		for tile in dict:
			seen[tile.y] = true
	for p in plan.placements:
		seen[p["tile"].y] = true
	for z in plan.zones.values():
		for tile in z["tiles"]:
			seen[tile.y] = true
	if plan.has_entrance:
		seen[plan.entrance.y] = true
	for tile in plan.exits:
		seen[tile.y] = true
	var out: Array[int] = []
	for y in seen:
		out.append(y)
	out.sort()
	return out


## The smallest grid (columns, rows) that holds everything the plan has, 1x1 at least.
static func content_bounds(plan) -> Vector2i:
	var w := 1
	var d := 1
	var tiles: Array = []
	for dict in [
		plan.floor_tiles, plan.hole_tiles, plan.pit_tiles, plan.wall_tiles, plan.water_tiles,
		plan.tile_props
	]:
		tiles.append(dict.keys())
	for p in plan.placements:
		tiles.append([p["tile"]])
	for z in plan.zones.values():
		tiles.append(z["tiles"].keys())
	tiles.append(plan.exits)
	if plan.has_entrance:
		tiles.append([plan.entrance])
	for group in tiles:
		for t in group:
			w = maxi(w, t.x + 1)
			d = maxi(d, t.z + 1)
	return Vector2i(w, d)


## Every storey in `floors` (or all the plan has) as {y: text}.
static func write_all(plan, floors: Array = [], opts: Dictionary = {}) -> Dictionary:
	var ys: Array = floors if not floors.is_empty() else floors_of(plan)
	var out := {}
	for y in ys:
		out[int(y)] = write_floor(plan, int(y), opts)
	return out


## The text of the storey at `y`. `opts`: `title` (the header's, the slug by default),
## `note_line` (its second comment line) and `size` (a Vector2i, the least grid wanted; the largest
## of it and the plan's own bounds wins).
static func write_floor(plan, y: int, opts: Dictionary = {}) -> String:
	var title: String = opts.get("title", String(plan.slug))
	var size: Vector2i = opts.get("size", Vector2i(1, 1))
	var note_line: String = opts.get("note_line", "")
	if note_line == "":
		note_line = DEFAULT_NOTE_LINE
	var bounds := content_bounds(plan)
	var width := maxi(size.x, bounds.x)
	var depth := maxi(size.y, bounds.y)

	# Stairs that the grid can carry on their own are drawn as characters.
	var stairs_chars := {}  # Vector3i -> char
	var legend := {}  # char -> "stairs dir=… face=…"
	var rest: Array = []  # what goes in [tiles]: [group, z, x, order, text]
	var order := 0
	for p in plan.placements:
		var tile: Vector3i = p["tile"]
		if tile.y != y:
			continue
		order += 1
		var ch := stairs_char(p)
		if ch != "" and not stairs_chars.has(tile):
			stairs_chars[tile] = ch
			legend[ch] = "stairs " + format_props(&"stairs", p["props"], y)
			continue
		var text := "%s %s" % [cell_name(tile.x, tile.z), String(p["kind"])]
		var props := format_props(p["kind"], p["props"], y)
		if props != "":
			text += " " + props
		rest.append([_group_of(p["kind"]), tile.z, tile.x, order, text])
	for tile in plan.tile_props:
		if tile.y != y:
			continue
		var props: Dictionary = plan.tile_props[tile].duplicate()
		if props.get("surface", "") == "ice" and plan.floor_tiles.has(tile):
			props.erase("surface")  # the grid says it: `i`
		var text := format_props(&"", props, y)
		if text == "":
			continue
		order += 1
		rest.append(
			[_tile_group(plan, tile, stairs_chars), tile.z, tile.x, order,
			"%s %s" % [cell_name(tile.x, tile.z), text]]
		)
	rest.sort_custom(_before)

	var lines: Array[String] = [
		"# %s - floor %d" % [title, y],
		note_line,
		"# Cell names (AB24) are the viewer's; columns A.. left to right, rows 1.. top to bottom.",
		"",
		"[floor]",
		"y = %d" % y,
		"",
		"[grid]",
	]
	for z in depth:
		var row := ""
		for x in width:
			row += _grid_char(plan, Vector3i(x, y, z), stairs_chars)
		lines.append(row)
	lines.append("")
	if not legend.is_empty():
		lines.append("[legend]")
		lines.append("# stairs: ^ > v < climb north/east/south/west, n e s w descend")
		var chars: Array = legend.keys()
		chars.sort()
		for ch in chars:
			lines.append("%s = %s" % [ch, legend[ch]])
		lines.append("")
	if not rest.is_empty():
		lines.append("[tiles]")
		var last = null
		for entry in rest:
			if entry[0] != last:
				lines.append("# %s" % entry[0])
				last = entry[0]
			lines.append(entry[4])
		lines.append("")
	var zone_lines := _zone_lines(plan, y)
	if not zone_lines.is_empty():
		lines.append("[zones]")
		lines.append_array(zone_lines)
		lines.append("")
	return "\n".join(lines)


# --------------------------------------------------------------------------
# The grid
# --------------------------------------------------------------------------


## The legend character of a stairs placement whose properties are `dir` and `face` and nothing
## else, "" for anything the grid cannot carry on its own.
static func stairs_char(placement: Dictionary) -> String:
	if placement["kind"] != &"stairs":
		return ""
	var props: Dictionary = placement["props"]
	if props.size() != 2 or not props.has("dir") or not props.has("face"):
		return ""
	var face := dir_letter(props["face"])
	if face == "":
		return ""
	match props["dir"]:
		"up":
			return UP_CHAR[face]
		"down":
			return DOWN_CHAR[face]
	return ""


static func _grid_char(plan, tile: Vector3i, stairs_chars: Dictionary) -> String:
	if stairs_chars.has(tile):
		return stairs_chars[tile]
	if plan.has_entrance and plan.entrance == tile:
		return "E"
	if plan.exits.has(tile):
		return "X"
	if plan.hole_tiles.has(tile):
		return ":"
	if plan.wall_tiles.has(tile):
		return "#"
	if plan.pit_tiles.has(tile):
		return "~" if plan.water_tiles.has(tile) else "_"
	if plan.water_tiles.has(tile):
		return "~"
	if plan.floor_tiles.has(tile):
		if plan.tile_props.get(tile, {}).get("surface", "") == "ice":
			return "i"
		return "."
	return "_"


# --------------------------------------------------------------------------
# [tiles]
# --------------------------------------------------------------------------


## The `# heading` a placement is listed under: its kind, except the importer's two merges.
static func _group_of(kind: StringName) -> String:
	match kind:
		&"cracked_wall":
			return "cracked"
		&"rival_spawn", &"special_spawn":
			return "spawn"
	return String(kind)


## The heading of a bare tile line: where the importer put it.
static func _tile_group(plan, tile: Vector3i, stairs_chars: Dictionary) -> String:
	if plan.has_entrance and plan.entrance == tile:
		return "start"
	if stairs_chars.has(tile):
		return "stairs"
	if plan.exits.has(tile):
		return "exit"
	return "notes"


static func _before(a: Array, b: Array) -> bool:
	for i in 4:
		if a[i] != b[i]:
			return a[i] < b[i]
	return false


## `name=value` tokens, the kind's own properties in the table's order, then the common ones, then
## whatever else (`custom.*`, names the table does not know) alphabetically.
static func format_props(kind: StringName, props: Dictionary, file_y: int) -> String:
	var names: Array[String] = []
	if Kinds.KINDS.has(kind):
		for name in Kinds.KINDS[kind]["props"]:
			if props.has(name):
				names.append(name)
	for name in COMMON_ORDER:
		if props.has(name) and not names.has(name):
			names.append(name)
	var others: Array[String] = []
	for name in props:
		if not names.has(name):
			others.append(name)
	others.sort()
	names.append_array(others)
	var tokens: Array[String] = []
	for name in names:
		tokens.append(token(name, Kinds.prop_type(kind, name), props[name], file_y))
	return " ".join(tokens)


## `name=value`, the value quoted when it holds a space.
static func token(name: String, type: String, value, file_y: int) -> String:
	var text := format_value(type, value, file_y)
	if text.contains(" ") or text.contains("\t"):
		text = '"%s"' % text
	return "%s=%s" % [name, text]


static func format_value(type: String, value, file_y: int) -> String:
	if value is Vector3i and type == "dir":
		return dir_letter(value)
	if value is Vector3i:
		return tile_ref(value, file_y)
	if value is Array:
		var parts: Array[String] = []
		for item in value:
			if item is Vector3i:
				parts.append(tile_ref(item, file_y))
			else:
				parts.append(str(item).replace('"', "'"))
		return (";" if type == "tiles" else ",").join(parts)
	if value is bool:
		return "true" if value else "false"
	return str(value).replace('"', "'")


## `N`, `E`, `S` or `W` for a direction vector, "" for anything else.
static func dir_letter(v) -> String:
	if v is Vector3i:
		for letter in Kinds.DIRECTIONS:
			if Kinds.DIRECTIONS[letter] == v:
				return letter
	return ""


## A tile as the file spells it: its cell name, then `@y` when it is not on the file's own storey.
static func tile_ref(tile: Vector3i, file_y: int) -> String:
	var text := cell_name(tile.x, tile.z)
	return text if tile.y == file_y else "%s@%d" % [text, tile.y]


## `AB24` for (27, 23): the viewer's spreadsheet naming, columns A.. and rows from 1.
static func cell_name(x: int, z: int) -> String:
	var column := ""
	var n := x + 1
	while n > 0:
		n -= 1
		column = char(65 + n % 26) + column
		n = floori(n / 26.0)
	return "%s%d" % [column, z + 1]


# --------------------------------------------------------------------------
# [zones]
# --------------------------------------------------------------------------


static func _zone_lines(plan, y: int) -> Array[String]:
	var out: Array[String] = []
	var names: Array = plan.zones.keys()
	names.sort()
	for name in names:
		var zone: Dictionary = plan.zones[name]
		var rows := {}  # z -> Array of x
		for tile in zone["tiles"]:
			if tile.y == y:
				if not rows.has(tile.z):
					rows[tile.z] = []
				rows[tile.z].append(tile.x)
		if rows.is_empty():
			continue
		var pieces := _zone_pieces(rows, y)
		var head := String(name)
		if not zone["tags"].is_empty():
			head += " " + token("tags", "list", zone["tags"], y)
		var extra: Array[String] = []
		var props: Dictionary = zone["props"]
		if props.has("note"):
			extra.append(token("note", "str", props["note"], y))
		var customs: Array[String] = []
		for key in props:
			if key != "note":
				customs.append(key)
		customs.sort()
		for key in customs:
			extra.append(token(key, "str", props[key], y))
		for i in pieces.size():
			var line := head
			if i == 0 and not extra.is_empty():
				line += " " + " ".join(extra)
			out.append(line + " " + pieces[i])
	return out


## A zone's tiles on one storey as `rect=A1:B2` and `tiles=…` tokens, one line's worth each:
## maximal runs along a row, runs of the same extent on neighbouring rows merged into rectangles,
## and what stays a single tile listed.
static func _zone_pieces(rows: Dictionary, y: int) -> Array[String]:
	var zs: Array = rows.keys()
	zs.sort()
	var open := {}  # "x0:x1" -> [x0, x1, z0, z1]
	var rects: Array = []
	for z in zs:
		var xs: Array = rows[z]
		xs.sort()
		var i := 0
		while i < xs.size():
			var j := i
			while j + 1 < xs.size() and xs[j + 1] == xs[j] + 1:
				j += 1
			var key := "%d:%d" % [xs[i], xs[j]]
			if open.has(key) and open[key][3] == z - 1:
				open[key][3] = z
			else:
				open[key] = [xs[i], xs[j], z, z]
				rects.append(open[key])
			i = j + 1
	rects.sort_custom(_rect_before)
	var pieces: Array[String] = []
	var singles: Array[String] = []
	for r in rects:
		if r[0] == r[1] and r[2] == r[3]:
			singles.append(tile_ref(Vector3i(r[0], y, r[2]), y))
		else:
			pieces.append(
				"rect=%s:%s" % [
					tile_ref(Vector3i(r[0], y, r[2]), y), tile_ref(Vector3i(r[1], y, r[3]), y)
				]
			)
	var at := 0
	while at < singles.size():
		pieces.append("tiles=" + ";".join(singles.slice(at, at + SINGLES_PER_LINE)))
		at += SINGLES_PER_LINE
	return pieces


static func _rect_before(a: Array, b: Array) -> bool:
	if a[2] != b[2]:
		return a[2] < b[2]
	return a[0] < b[0]


# --------------------------------------------------------------------------
# Rules
# --------------------------------------------------------------------------


## `rules.cfg`'s text with `[water] emerge` set to `value`, every other byte as it was: the key's
## line is replaced when it is there, added under `[water]` when only the section is, and a
## section appended otherwise.
static func patch_emerge(text: String, value: String) -> String:
	var line := 'emerge="%s"' % value
	var lines := text.split("\n")
	var in_water := false
	var water_at := -1
	for i in lines.size():
		var s := lines[i].strip_edges()
		if s.begins_with("[") and s.ends_with("]"):
			in_water = s == "[water]"
			if in_water:
				water_at = i
			continue
		if in_water and (s.begins_with("emerge=") or s.begins_with("emerge =")):
			lines[i] = line
			return "\n".join(lines)
	if water_at >= 0:
		var out := Array(lines)
		out.insert(water_at + 1, line)
		return "\n".join(PackedStringArray(out))
	var tail := text
	if not tail.is_empty() and not tail.ends_with("\n"):
		tail += "\n"
	if not tail.is_empty():
		tail += "\n"
	return tail + "[water]\n" + line + "\n"
