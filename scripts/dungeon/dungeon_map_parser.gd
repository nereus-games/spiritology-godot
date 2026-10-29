## Reads a dungeon's map files into a [DungeonPlan]: one `floor_*.map` per storey, in
## `data/dungeons/<slug>/`.
##
## A map file is sections. `[floor]` gives the storey (`y = 0`); `[grid]` is the map, one
## character per tile, x to the right and z downwards, the top-left character being tile (0, 0);
## `[legend]` says what each further character is; `[tiles]` annotates single tiles; `[zones]`
## names areas. Inside `[grid]` every line is the map, verbatim. Everywhere else a line starting
## with `#` is a comment and a blank line is nothing.
##
##   [floor]
##   y = 0
##   [grid]
##   ##########
##   #E..T..c.#
##   ##########
##   [legend]
##   T = trap type=poison
##   c = chest loot=rune_stone,spade
##   [tiles]
##   3,1 note="the rival waits here" tags=unreachable_ok
##   7,1 chest trapped=true
##   [zones]
##   hall tags=safe,no_teleport rect=1,1:3,1
##
## The grid's own characters: `.` floor, `#` or space nothing, `~` a hole, `_` a pit, `E` the
## entrance, `X` an exit. Any other character must be in the legend, as `char = kind props…`.
## A `[tiles]` line is `x,z` then either properties, or a kind and its properties. Values with
## spaces are quoted.
##
## A problem is recorded as an issue in the plan, never raised: the validator reports the lot at
## once, with the file and line.
##
## No `class_name` (the CLI class-cache trap): referenced by `preload`.
extends RefCounted

const Kinds := preload("res://scripts/dungeon/dungeon_kinds.gd")
const Plan := preload("res://scripts/dungeon/dungeon_plan.gd")

const CORE_CHARS := ".# ~_EX"

var _plan
var _file := ""
var _line := 0
var _y := 0
var _has_y := false


## Reads `res://data/dungeons/<slug>/*.map`, in file-name order.
static func load_slug(slug: StringName, root: String = "res://data/dungeons/") -> Plan:
	var plan := Plan.new()
	plan.slug = slug
	var dir_path := root.path_join(String(slug))
	var dir := DirAccess.open(dir_path)
	if dir == null:
		plan.add_issue("error", "NO_DIRECTORY", null, dir_path)
		return plan
	var names: Array[String] = []
	for f in dir.get_files():
		if f.ends_with(".map"):
			names.append(f)
	names.sort()
	if names.is_empty():
		plan.add_issue("error", "NO_MAP_FILES", null, dir_path)
	for f in names:
		var text := FileAccess.get_file_as_string(dir_path.path_join(f))
		new().read_floor(plan, text, "%s/%s" % [slug, f])
	return plan


## The slugs of the dungeons that have a directory of maps.
static func slugs(root: String = "res://data/dungeons/") -> Array[StringName]:
	var out: Array[StringName] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	for d in dir.get_directories():
		out.append(StringName(d))
	out.sort()
	return out


## Reads the text of ONE storey into `plan`. `file` is only what issues will say.
func read_floor(plan: Plan, text: String, file: String) -> void:
	_plan = plan
	_file = file
	_y = 0
	_has_y = false
	var section := ""
	var grid_rows: Array[String] = []
	var grid_line := 0
	var legend := {}
	var tile_lines: Array = []  # [line number, text]
	var zone_lines: Array = []
	var number := 0
	for raw in text.split("\n"):
		number += 1
		var line := raw.trim_suffix("\r")
		if section == "grid" and not line.strip_edges().begins_with("["):
			if grid_rows.is_empty():
				grid_line = number
			grid_rows.append(line)
			continue
		var s := line.strip_edges()
		if s.is_empty() or s.begins_with("#"):
			continue
		if s.begins_with("[") and s.ends_with("]"):
			section = s.substr(1, s.length() - 2)
			if not ["floor", "grid", "legend", "tiles", "zones"].has(section):
				_line = number
				_issue("error", "UNKNOWN_SECTION", null, [section])
			continue
		_line = number
		match section:
			"floor":
				_read_floor_line(s)
			"legend":
				_read_legend_line(s, legend)
			"tiles":
				tile_lines.append([number, s])
			"zones":
				zone_lines.append([number, s])
			_:
				_issue("error", "LINE_OUTSIDE_SECTION", null, [s])
	if not _has_y:
		_line = 0
		_issue("error", "MISSING_FLOOR_Y", null)
	# Trailing blank rows of the grid carry nothing.
	while not grid_rows.is_empty() and grid_rows[-1].strip_edges().is_empty():
		grid_rows.pop_back()
	_read_grid(grid_rows, grid_line, legend)
	for entry in tile_lines:
		_line = entry[0]
		_read_tile_line(entry[1])
	for entry in zone_lines:
		_line = entry[0]
		_read_zone_line(entry[1])


# --------------------------------------------------------------------------
# Sections
# --------------------------------------------------------------------------


func _read_floor_line(s: String) -> void:
	var parts := s.split("=", true, 1)
	if parts.size() == 2 and parts[0].strip_edges() == "y" and parts[1].strip_edges().is_valid_int():
		_y = parts[1].strip_edges().to_int()
		_has_y = true
	else:
		_issue("error", "BAD_LINE", null, [s])


func _read_legend_line(s: String, legend: Dictionary) -> void:
	var at := s.find(" = ")
	if at != 1:
		_issue("error", "BAD_LINE", null, [s])
		return
	var key := s.substr(0, 1)
	var rest := s.substr(at + 3)
	if CORE_CHARS.contains(key):
		_issue("error", "LEGEND_CORE_CHAR", null, [key])
		return
	var tokens := _tokens(rest)
	if tokens.is_empty():
		_issue("error", "BAD_LINE", null, [s])
		return
	var kind := StringName(tokens[0])
	if not Kinds.has_kind(kind):
		_issue("error", "UNKNOWN_KIND", null, [String(kind)])
		return
	legend[key] = {"kind": kind, "tokens": tokens.slice(1)}


func _read_grid(rows: Array[String], first_line: int, legend: Dictionary) -> void:
	for r in rows.size():
		_line = first_line + r
		var row := rows[r]
		for x in row.length():
			var ch := row[x]
			var tile := Vector3i(x, _y, r)
			match ch:
				".":
					_plan.floor_tiles[tile] = true
				"#", " ":
					pass
				"~":
					_plan.hole_tiles[tile] = true
				"_":
					_plan.pit_tiles[tile] = true
				"E":
					_plan.floor_tiles[tile] = true
					if _plan.has_entrance:
						_issue("error", "DUPLICATE_ENTRANCE", tile)
					_plan.entrance = tile
					_plan.has_entrance = true
				"X":
					_plan.floor_tiles[tile] = true
					_plan.exits.append(tile)
				_:
					if not legend.has(ch):
						_issue("error", "UNKNOWN_CHAR", tile, [ch])
						continue
					_place(legend[ch]["kind"], tile, legend[ch]["tokens"], true)


func _read_tile_line(s: String) -> void:
	var tokens := _tokens(s)
	var tile = _parse_tile(tokens[0])
	if tile == null:
		_issue("error", "BAD_TILE", null, [tokens[0]])
		return
	var rest := tokens.slice(1)
	if not rest.is_empty() and not rest[0].contains("="):
		var kind := StringName(rest[0])
		if not Kinds.has_kind(kind):
			_issue("error", "UNKNOWN_KIND", tile, [String(kind)])
			return
		_place(kind, tile, rest.slice(1))
		return
	var props := _props(&"", rest, tile)
	if not _plan.tile_props.has(tile):
		_plan.tile_props[tile] = {}
	_plan.tile_props[tile].merge(props, true)


func _read_zone_line(s: String) -> void:
	var tokens := _tokens(s)
	var name: String = tokens[0]
	var tags: Array = []
	var tiles: Array[Vector3i] = []
	for t in tokens.slice(1):
		var kv: PackedStringArray = String(t).split("=", true, 1)
		if kv.size() != 2:
			_issue("error", "BAD_LINE", null, [s])
			return
		match kv[0]:
			"tags":
				tags = Array(kv[1].split(",", false))
			"rect":
				var corners: PackedStringArray = kv[1].split(":")
				var a = _parse_tile(corners[0])
				var b = _parse_tile(corners[-1])
				if corners.size() != 2 or a == null or b == null:
					_issue("error", "BAD_VALUE", null, [t])
					return
				for x in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
					for z in range(mini(a.z, b.z), maxi(a.z, b.z) + 1):
						tiles.append(Vector3i(x, _y, z))
			"tiles":
				for part in kv[1].split(";", false):
					var c = _parse_tile(part)
					if c == null:
						_issue("error", "BAD_VALUE", null, [t])
						return
					tiles.append(c)
			_:
				_issue("error", "BAD_VALUE", null, [t])
				return
	if tiles.is_empty():
		_issue("error", "BAD_LINE", null, [s])
		return
	for tile in tiles:
		_plan.add_zone_tile(name, tags, tile)


# --------------------------------------------------------------------------
# Placements and values
# --------------------------------------------------------------------------


## `from_grid`: the placement is a character of the map, so a kind that is "any" floor is floor
## there — it was drawn on a tile. On a `[tiles]` line it leaves the tile as the grid has it.
func _place(kind: StringName, tile: Vector3i, tokens: Array, from_grid: bool = false) -> void:
	var def: Dictionary = Kinds.KINDS[kind]
	var props := _props(kind, tokens, tile)
	match def["floor"]:
		"yes":
			_plan.floor_tiles[tile] = true
		"any":
			if from_grid:
				_plan.floor_tiles[tile] = true
		"no":
			_plan.floor_tiles.erase(tile)
	if def.get("pit", false):
		_plan.pit_tiles[tile] = true
	_plan.add_placement(kind, tile, props, "%s:%d" % [_file, _line])


## Typed properties from `key=value` tokens. An unknown name is kept as a string, so that the
## validator can say so.
func _props(kind: StringName, tokens: Array, _tile: Vector3i) -> Dictionary:
	var out := {}
	for t in tokens:
		var kv: PackedStringArray = String(t).split("=", true, 1)
		if kv.size() != 2:
			_issue("error", "BAD_VALUE", null, [t])
			continue
		var name := kv[0]
		var raw := kv[1]
		var type := Kinds.prop_type(kind, name) if kind != &"" else _bare_type(name)
		if type == "":
			out[name] = raw
			continue
		var value = _convert(type, raw)
		if value == null:
			_issue("error", "BAD_VALUE", null, [t])
			continue
		out[name] = value
	return out


## A bare tile line carries only the common properties.
func _bare_type(name: String) -> String:
	return Kinds.COMMON.get(name, "str" if name.begins_with("custom.") else "")


func _convert(type: String, raw: String):
	if type.begins_with("enum:"):
		return raw if type.substr(5).split("|").has(raw) else null
	match type:
		"bool":
			if raw == "true" or raw == "false":
				return raw == "true"
			return null
		"int":
			return raw.to_int() if raw.is_valid_int() else null
		"float":
			return raw.to_float() if raw.is_valid_float() else null
		"str":
			return raw
		"list":
			return Array(raw.split(",", false))
		"dir":
			return Kinds.DIRECTIONS[raw] if Kinds.DIRECTIONS.has(raw) else null
		"tile":
			return _parse_tile(raw)
		"tiles":
			var out: Array[Vector3i] = []
			for part in raw.split(";", false):
				var c = _parse_tile(part)
				if c == null:
					return null
				out.append(c)
			return out
	return null


## `x,z` on this storey, or `x,y,z`; null when it is neither.
func _parse_tile(s: String):
	var parts := s.strip_edges().split(",")
	for p in parts:
		if not p.strip_edges().is_valid_int():
			return null
	if parts.size() == 2:
		return Vector3i(parts[0].to_int(), _y, parts[1].to_int())
	if parts.size() == 3:
		return Vector3i(parts[0].to_int(), parts[1].to_int(), parts[2].to_int())
	return null


## Splits on whitespace, keeping a quoted value whole: `note="a b"` is one token, `note=a b`.
func _tokens(s: String) -> Array:
	var out: Array = []
	var cur := ""
	var quoted := false
	for ch in s:
		if ch == '"':
			quoted = not quoted
		elif (ch == " " or ch == "\t") and not quoted:
			if not cur.is_empty():
				out.append(cur)
				cur = ""
		else:
			cur += ch
	if not cur.is_empty():
		out.append(cur)
	if quoted:
		_issue("error", "UNCLOSED_QUOTE", null, [s])
	return out


func _issue(severity: String, code: String, tile, args: Array = []) -> void:
	_plan.add_issue(severity, code, tile, "%s:%d" % [_file, _line], args)
