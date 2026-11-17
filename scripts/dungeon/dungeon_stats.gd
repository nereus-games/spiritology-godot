## Numbers about a [DungeonPlan]: tiles and placements per storey and in total, spawn points
## against what `rules.cfg` asks for, zones, exits, how much of the floor the validator reaches,
## and the issue counts.
##
## [method compute] returns plain data (so a check can read it and `--json` can print it);
## [method format_text] lays it out as a table. Pure functions, no nodes.
##
## No `class_name` (the CLI class-cache trap): referenced by `preload`.
extends RefCounted

const View := preload("res://scripts/dungeon/dungeon_view.gd")

## The rows of the table that count tiles: label, key in a storey's dictionary.
const TILE_ROWS := [
	["floor tiles", "floor"],
	["  of which ice", "ice"],
	["  of which reachable", "reachable"],
	["water tiles", "water"],
	["wall tiles", "wall"],
	["hole tiles", "hole"],
	["pit tiles (under planks)", "pit"],
	["tiles in a zone", "zone_tiles"],
	["tiles with tags", "tagged_tiles"],
	["entrance", "entrance"],
	["exits", "exits"],
	["rival spawn points", "rival_spawns"],
	["special spawn points", "special_spawns"],
]


## `reached` is [method DungeonValidator.reachable_from_entrance]; `issues` is what
## [method DungeonValidator.validate] returned.
static func compute(plan, issues: Array, reached: Dictionary) -> Dictionary:
	var kinds := {}
	for p in plan.placements:
		kinds[String(p["kind"])] = true
	var kind_names: Array = kinds.keys()
	kind_names.sort()
	var storeys: Array = []
	for y in View.floors(plan):
		storeys.append(_storey(plan, y, issues, reached))
	var total := _storey(plan, null, issues, reached)
	var wanted := int(plan.rule("spawn_at_entry", "rivals", 0))
	var zones := {}
	for name in plan.zones:
		var ys := {}
		for tile in plan.zones[name]["tiles"]:
			ys[tile.y] = true
		var floors: Array = ys.keys()
		floors.sort()
		zones[name] = {
			"tags": plan.zones[name]["tags"].duplicate(),
			"tiles": plan.zones[name]["tiles"].size(),
			"floors": floors,
		}
	var exits: Array = []
	for tile in plan.exits:
		exits.append(View.tile_name(tile, true))
	var codes := {}
	for issue in issues:
		codes[issue["code"]] = int(codes.get(issue["code"], 0)) + 1
	return {
		"slug": String(plan.slug),
		"floors": storeys,
		"total": total,
		"kinds": kind_names,
		"rivals_at_entry": wanted,
		"rival_spawn_points": total["rival_spawns"],
		"spawn_points_enough": total["rival_spawns"] >= wanted,
		"zones": zones,
		"entrance": View.tile_name(plan.entrance, true) if plan.has_entrance else "",
		"exits": exits,
		"issue_codes": codes,
	}


## The counts for storey `y`, or for everything when `y` is null.
static func _storey(plan, y, issues: Array, reached: Dictionary) -> Dictionary:
	var out := {
		"floor": 0,
		"ice": 0,
		"reachable": 0,
		"water": 0,
		"wall": 0,
		"hole": 0,
		"pit": 0,
		"zone_tiles": 0,
		"tagged_tiles": 0,
		"entrance": 0,
		"exits": 0,
		"rival_spawns": 0,
		"special_spawns": 0,
		"placements": {},
		"errors": 0,
		"warnings": 0,
		"waived": 0,
	}
	if y != null:
		out["y"] = y
	for tile in plan.floor_tiles:
		if y != null and tile.y != y:
			continue
		out["floor"] += 1
		if plan.tile_props.get(tile, {}).get("surface", "") == "ice":
			out["ice"] += 1
		if reached.has(tile):
			out["reachable"] += 1
	out["water"] = _count(plan.water_tiles, y)
	out["wall"] = _count(plan.wall_tiles, y)
	out["hole"] = _count(plan.hole_tiles, y)
	out["pit"] = _count(plan.pit_tiles, y)
	var in_zone := {}
	for z in plan.zones.values():
		for tile in z["tiles"]:
			if y == null or tile.y == y:
				in_zone[tile] = true
	out["zone_tiles"] = in_zone.size()
	var tagged := {}
	for tile in plan.tile_props:
		if not plan.tile_props[tile].get("tags", []).is_empty() and (y == null or tile.y == y):
			tagged[tile] = true
	for p in plan.placements:
		var tile: Vector3i = p["tile"]
		if y != null and tile.y != y:
			continue
		var kind := String(p["kind"])
		out["placements"][kind] = int(out["placements"].get(kind, 0)) + 1
		if not p["props"].get("tags", []).is_empty():
			tagged[tile] = true
		if p["kind"] == &"rival_spawn":
			out["rival_spawns"] += 1
		elif p["kind"] == &"special_spawn":
			out["special_spawns"] += 1
	out["tagged_tiles"] = tagged.size()
	if plan.has_entrance and (y == null or plan.entrance.y == y):
		out["entrance"] = 1
	for tile in plan.exits:
		if y == null or tile.y == y:
			out["exits"] += 1
	for issue in issues:
		var tile = issue["tile"]
		if y != null and (tile == null or tile.y != y):
			continue
		if issue["severity"] == "error":
			out["errors"] += 1
		else:
			out["warnings"] += 1
			if issue.has("waived"):
				out["waived"] += 1
	var box := View.tight_bounds(plan, y) if y != null else View.bounds(plan)
	out["bounds"] = _box_name(box)
	out["size"] = "%dx%d" % [box.size.x, box.size.y]
	return out


static func _count(tiles: Dictionary, y) -> int:
	if y == null:
		return tiles.size()
	var n := 0
	for tile in tiles:
		if tile.y == y:
			n += 1
	return n


static func _box_name(box: Rect2i) -> String:
	if box.size == Vector2i.ZERO:
		return "-"
	var last := box.end - Vector2i.ONE
	return (
		"%s:%s" % [View.cell_name(box.position.x, box.position.y), View.cell_name(last.x, last.y)]
	)


## The statistics as a table: one column per storey, then the total.
static func format_text(stats: Dictionary) -> String:
	var storeys: Array = stats["floors"]
	var header: Array[String] = [stats["slug"]]
	for s in storeys:
		header.append("floor %d" % s["y"])
	header.append("total")
	var rows: Array = [header]
	for row in TILE_ROWS:
		rows.append(_row(row[0], row[1], storeys, stats["total"]))
	for kind in stats["kinds"]:
		var line: Array[String] = ["placed: " + kind]
		for s in storeys:
			line.append(str(s["placements"].get(kind, 0)))
		line.append(str(stats["total"]["placements"].get(kind, 0)))
		rows.append(line)
	rows.append(_row("issues: errors", "errors", storeys, stats["total"]))
	rows.append(_row("issues: warnings", "warnings", storeys, stats["total"]))
	rows.append(_row("  of which waived", "waived", storeys, stats["total"]))
	rows.append(_row("size (tiles)", "size", storeys, stats["total"]))
	rows.append(_row("bounding box", "bounds", storeys, stats["total"]))
	var out := _table(rows)
	var total: Dictionary = stats["total"]
	out += (
		"\nrivals at entry (rules.cfg): %d; rival spawn points on the maps: %d (%s)\n"
		% [
			stats["rivals_at_entry"],
			total["rival_spawns"],
			"enough" if stats["spawn_points_enough"] else "TOO FEW",
		]
	)
	out += "entrance: %s\n" % (stats["entrance"] if stats["entrance"] != "" else "none")
	out += "exits: %s\n" % (", ".join(stats["exits"]) if not stats["exits"].is_empty() else "none")
	out += (
		"reachable from the entrance (validator): %d of %d floor tiles\n"
		% [total["reachable"], total["floor"]]
	)
	var names: Array = stats["zones"].keys()
	names.sort()
	if names.is_empty():
		out += "zones: none\n"
	else:
		out += "zones:\n"
		for name in names:
			var z: Dictionary = stats["zones"][name]
			var on_floors: Array[String] = []
			for y in z["floors"]:
				on_floors.append(str(y))
			out += (
				"  %s  %d tile(s) on floor %s  [%s]\n"
				% [name, z["tiles"], ", ".join(on_floors), ",".join(z["tags"])]
			)
	var codes: Dictionary = stats["issue_codes"]
	if not codes.is_empty():
		var parts: Array[String] = []
		var keys: Array = codes.keys()
		keys.sort()
		for code in keys:
			parts.append("%s x%d" % [code, codes[code]])
		out += "issue codes: %s\n" % ", ".join(parts)
	return out


static func _row(label: String, key: String, storeys: Array, total: Dictionary) -> Array[String]:
	var row: Array[String] = [label]
	for s in storeys:
		row.append(str(s[key]))
	row.append(str(total[key]))
	return row


## Left-aligned first column, right-aligned numbers.
static func _table(rows: Array) -> String:
	var widths: Array[int] = []
	for row in rows:
		for i in row.size():
			if widths.size() <= i:
				widths.append(0)
			widths[i] = maxi(widths[i], str(row[i]).length())
	var out := ""
	for row in rows:
		var line := ""
		for i in row.size():
			if i == 0:
				line += str(row[i]).rpad(widths[0])
			else:
				line += "  " + str(row[i]).lpad(widths[i])
		out += line + "\n"
	return out


## The statistics as JSON text, keys sorted so that two runs compare.
static func to_json(stats: Dictionary) -> String:
	return JSON.stringify(stats, "  ", true)
