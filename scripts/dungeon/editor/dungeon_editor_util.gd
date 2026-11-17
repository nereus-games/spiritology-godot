## Pure helpers of the dungeon editor's model: what a property value may be, which names a
## dungeon or a zone may bear, a rectangle of tiles, the text of a plan that says the same for two
## plans that say the same thing, and the little readings of a map file the model needs at load.
##
## No `class_name` (the CLI class-cache trap): referenced by `preload`.
extends RefCounted

const Kinds := preload("res://scripts/dungeon/dungeon_kinds.gd")
const Writer := preload("res://scripts/dungeon/dungeon_map_writer.gd")


static func valid_slug(text: String) -> bool:
	if text.is_empty():
		return false
	for ch in text:
		if not ((ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "_"):
			return false
	return true


static func valid_zone_name(text: String) -> bool:
	if text.is_empty():
		return false
	for ch in text:
		if ch == " " or ch == "=" or ch == '"' or ch == "#" or ch == "\t" or ch == ":":
			return false
	return true


static func rect_tiles(a: Vector3i, b: Vector3i) -> Array:
	var out: Array = []
	for z in range(mini(a.z, b.z), maxi(a.z, b.z) + 1):
		for x in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
			out.append(Vector3i(x, a.y, z))
	return out


## "" when `props` fit `kind`'s table, else the name of the first property that does not.
static func check_props(kind: StringName, props: Dictionary) -> String:
	for name in props:
		var type := Kinds.prop_type(kind, name)
		if type == "" or not value_ok(type, props[name]):
			return String(name)
	return ""


static func value_ok(type: String, value) -> bool:
	if type.begins_with("enum:"):
		return value is String and type.substr(5).split("|").has(value)
	match type:
		"bool":
			return value is bool
		"int":
			return typeof(value) == TYPE_INT
		"float":
			return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT
		"str":
			return value is String and not value.contains('"')
		"list":
			if not value is Array:
				return false
			for item in value:
				if not item is String or item.contains('"') or item.contains(","):
					return false
			return true
		"dir":
			return value is Vector3i and Kinds.DIRECTIONS.values().has(value)
		"tile":
			return value is Vector3i
		"tiles":
			if not value is Array:
				return false
			for item in value:
				if not item is Vector3i:
					return false
			return true
	return false


## A text that is the same for two plans that say the same thing: terrain, entrance and exits,
## placements with their properties, tile properties and zones. Not the sources, the uids, the
## order, nor zones with no tile (a file cannot hold one).
static func canonical(p) -> String:
	var lines: Array[String] = []
	for pair in [
		["floor", p.floor_tiles],
		["hole", p.hole_tiles],
		["pit", p.pit_tiles],
		["wall", p.wall_tiles],
		["water", p.water_tiles]
	]:
		for tile in pair[1]:
			lines.append("%s %s" % [pair[0], tile_text(tile)])
	if p.has_entrance:
		lines.append("entrance %s" % tile_text(p.entrance))
	for tile in p.exits:
		lines.append("exit %s" % tile_text(tile))
	for q in p.placements:
		lines.append(
			(
				"place %s %s %s"
				% [q["kind"], tile_text(q["tile"]), Writer.format_props(q["kind"], q["props"], 0)]
			)
		)
	for tile in p.tile_props:
		lines.append(
			"props %s %s" % [tile_text(tile), Writer.format_props(&"", p.tile_props[tile], 0)]
		)
	for name in p.zones:
		var z: Dictionary = p.zones[name]
		if z["tiles"].is_empty():
			continue
		lines.append(
			(
				"zone %s %s %s"
				% [
					name,
					",".join(PackedStringArray(z["tags"])),
					Writer.format_props(&"", z["props"], 0)
				]
			)
		)
		for tile in z["tiles"]:
			lines.append("zonetile %s %s" % [name, tile_text(tile)])
	lines.sort()
	return "\n".join(lines)


static func tile_text(tile: Vector3i) -> String:
	return "%d,%d,%d" % [tile.x, tile.y, tile.z]


## Columns and rows of the `[grid]` of a map file's text.
static func grid_extent(text: String) -> Vector2i:
	var in_grid := false
	var rows := 0
	var width := 0
	var pending := 0
	for raw in text.split("\n"):
		var line := raw.trim_suffix("\r")
		if in_grid and line.strip_edges().begins_with("["):
			break
		if line.strip_edges() == "[grid]":
			in_grid = true
			continue
		if in_grid:
			if line.strip_edges().is_empty():
				pending += 1
				continue
			rows += 1 + pending
			pending = 0
			width = maxi(width, line.length())
	return Vector2i(width, rows)


## The name in a file's first comment, `# <title> - floor <y>`, or `fallback`.
static func title_of(text: String, fallback: String) -> String:
	var first := text.get_slice("\n", 0).strip_edges()
	var at := first.rfind(" - floor ")
	if first.begins_with("# ") and at > 2:
		return first.substr(2, at - 2)
	return fallback


static func write_text(path: String, text: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	file.close()
	return OK
