## What the dungeon preview tools share: spreadsheet-style cell names, the extent of a plan, the
## kind of terrain a tile is, and which tiles carry an issue.
##
## Pure functions over a [DungeonPlan], no nodes: the ASCII dump, the PNG renderer and the
## statistics all read a plan through these, so that "AB24" means the same tile everywhere.
##
## No `class_name` (the CLI class-cache trap): referenced by `preload`.
extends RefCounted

const Kinds := preload("res://scripts/dungeon/dungeon_kinds.gd")

const FACES := {
	Vector3i(0, 0, -1): "N", Vector3i(1, 0, 0): "E", Vector3i(0, 0, 1): "S", Vector3i(-1, 0, 0): "W"
}


## `0` is A, `25` is Z, `26` is AA: the viewer's column names.
static func column_name(x: int) -> String:
	var n := x + 1
	var out := ""
	while n > 0:
		var r := (n - 1) % 26
		out = String.chr(65 + r) + out
		n = (n - 1) / 26
	return out


## `AB24` for tile (27, _, 23): column letters, then the row counted from 1.
static func cell_name(x: int, z: int) -> String:
	return "%s%d" % [column_name(x), z + 1]


## [method cell_name] of a tile, with `@y` appended when `with_floor` is set.
static func tile_name(tile: Vector3i, with_floor: bool = false) -> String:
	var name := cell_name(tile.x, tile.z)
	return "%s@%d" % [name, tile.y] if with_floor else name


## `AB24:AF30` as a rectangle of tiles (corners in any order), or null.
static func parse_rect(text: String):
	var parts := text.split(":")
	if parts.size() != 2:
		return null
	var a = Kinds.cell_tile(parts[0].strip_edges())
	var b = Kinds.cell_tile(parts[1].strip_edges())
	if a == null or b == null:
		return null
	var lo := Vector2i(mini(a.x, b.x), mini(a.y, b.y))
	var hi := Vector2i(maxi(a.x, b.x), maxi(a.y, b.y))
	return Rect2i(lo, hi - lo + Vector2i.ONE)


## Every storey that holds any tile, lowest first.
static func floors(plan) -> Array[int]:
	var seen := {}
	for tiles in _tile_sets(plan):
		for tile in tiles:
			seen[tile.y] = true
	var out: Array[int] = []
	for y in seen:
		out.append(y)
	out.sort()
	return out


## The smallest rectangle (in tiles) holding every tile of storey `y`, or of all storeys when
## `y` is null, and the origin: the viewer's grid starts at A1, so the rectangle always does.
static func bounds(plan, y = null) -> Rect2i:
	var tight := _extent(plan, y)
	if tight.size == Vector2i.ZERO:
		return tight
	var lo := Vector2i(mini(0, tight.position.x), mini(0, tight.position.y))
	var hi := tight.end
	return Rect2i(lo, hi - lo)


## The tight rectangle of the tiles that exist on storey `y` (no forced origin), or an empty one.
static func tight_bounds(plan, y: int) -> Rect2i:
	return _extent(plan, y)


static func _extent(plan, y) -> Rect2i:
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-(1 << 30), -(1 << 30))
	var any := false
	for tiles in _tile_sets(plan):
		for tile in tiles:
			if y != null and tile.y != y:
				continue
			any = true
			lo = Vector2i(mini(lo.x, tile.x), mini(lo.y, tile.z))
			hi = Vector2i(maxi(hi.x, tile.x), maxi(hi.y, tile.z))
	if not any:
		return Rect2i()
	return Rect2i(lo, hi - lo + Vector2i.ONE)


## What the grid says a tile is: `ice`, `floor`, `water`, `wall`, `hole` or `empty`. A plank over
## water is `water` with floor on it; use [method DungeonPlan.is_floor] for walkability.
static func terrain(plan, tile: Vector3i) -> StringName:
	if plan.water_tiles.has(tile):
		return &"water"
	if plan.floor_tiles.has(tile):
		if plan.tile_props.get(tile, {}).get("surface", "") == "ice":
			return &"ice"
		return &"floor"
	if plan.wall_tiles.has(tile):
		return &"wall"
	if plan.hole_tiles.has(tile) or plan.pit_tiles.has(tile):
		return &"hole"
	return &"empty"


## Tile -> "error", "waived" or "warning": the worst issue standing on each tile. Issues with no
## tile are left out.
static func issue_tiles(issues: Array) -> Dictionary:
	var out := {}
	for issue in issues:
		if issue["tile"] == null:
			continue
		var state := "error"
		if issue["severity"] != "error":
			state = "waived" if issue.has("waived") else "warning"
		var tile: Vector3i = issue["tile"]
		if not out.has(tile) or _rank(state) > _rank(out[tile]):
			out[tile] = state
	return out


static func _rank(state: String) -> int:
	return {"warning": 0, "waived": 1, "error": 2}[state]


## The placements of `kind` on the plan.
static func placements_of(plan, kind: StringName) -> Array:
	var out: Array = []
	for p in plan.placements:
		if p["kind"] == kind:
			out.append(p)
	return out


## `N`, `E`, `S` or `W` for a unit direction, "" otherwise.
static func face_letter(dir) -> String:
	return FACES.get(dir, "")


static func _tile_sets(plan) -> Array:
	return [plan.floor_tiles, plan.water_tiles, plan.wall_tiles, plan.hole_tiles, plan.pit_tiles]
