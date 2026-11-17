## The dungeon editor's model: a working [DungeonPlan], every edit a command on an undo stack,
## load, validate and save. No nodes and no UI, so the whole of it is checked headless.
##
## Every operation is ONE undoable command, however many tiles it touches (`begin`/`commit` group
## several into one, which is what a brush stroke does). A command is a journal of what it
## overwrote: undo puts every old value back, redo puts the new ones back, and the plan comes out
## exactly as it was — `canonical(plan)` is how the checks say "exactly".
##
## Coordinates are tiles (Vector3i: x, floor, z) with x and z from 0. A tile is reached by cell
## name (`AB24`) in the files and in the UI, as in the designers' viewer.
##
## What the editor keeps in step with the parser: a placement's floor rule (a trap makes its tile
## floor, stairs make it not-floor, a bridge makes a floor over a pit, and over water when it says
## so), so that the plan the editor holds is the plan the written files give back.
##
## No `class_name` (the CLI class-cache trap): referenced by `preload`.
extends "res://scripts/dungeon/editor/dungeon_editor_journal.gd"

const Kinds := preload("res://scripts/dungeon/dungeon_kinds.gd")
const Parser := preload("res://scripts/dungeon/dungeon_map_parser.gd")
const Writer := preload("res://scripts/dungeon/dungeon_map_writer.gd")
const Validator := preload("res://scripts/dungeon/dungeon_validator.gd")
const Util := preload("res://scripts/dungeon/editor/dungeon_editor_util.gd")

const DEFAULT_ROOT := "res://data/dungeons/"
const TERRAINS: Array[StringName] = [&"floor", &"ice", &"water", &"wall", &"empty", &"hole"]
## The grid a new dungeon starts with.
const NEW_SIZE := Vector2i(24, 24)

var slug: StringName = &""
var root := DEFAULT_ROOT
## The header's name of the dungeon, as the files have it.
var title := ""
## The second comment line of the files, kept as the designers or the importer left it ("" for
## the writer's own).
var header_note := ""
## The grid the files had when loaded: saves never write a smaller one.
var grid_size := NEW_SIZE
var floors: Array[int] = [0]
## What the parser could not read at load, kept until a save writes the readable remainder.
var load_issues: Array = []
## Why the last refused operation was refused: a code, "" after a success.
var last_error := ""
## The files the last save wrote.
var last_written: Array[String] = []
## The uid of the matching stairs `place_stairs` put on the next storey, or -1.
var last_partner_uid := -1

var _next_uid := 1
var _emerge_loaded := ""
var _rules_text_loaded := ""

# --------------------------------------------------------------------------
# Loading, saving
# --------------------------------------------------------------------------


## A new, empty dungeon with one storey.
func new_dungeon(new_slug: StringName, new_root: String = DEFAULT_ROOT) -> void:
	_reset()
	slug = new_slug
	root = new_root
	plan.slug = new_slug
	title = String(new_slug)
	floors = [0]
	changed.emit()


## Reads `<root>/<slug>/` : the plan through the parser, and the storeys, the grid's size and the
## title from the files themselves. A missing or partial dungeon loads as what there is of it:
## `load_issues` says what was wrong.
func load_dungeon(load_slug: StringName, load_root: String = DEFAULT_ROOT) -> void:
	_reset()
	slug = load_slug
	root = load_root
	plan = Parser.load_slug(load_slug, load_root)
	load_issues = plan.issues.duplicate()
	plan.issues = []
	title = String(load_slug)
	grid_size = Vector2i(1, 1)
	var ys := {}
	for y in Writer.floors_of(plan):
		ys[y] = true
	var dir_path := load_root.path_join(String(load_slug))
	var dir := DirAccess.open(dir_path)
	var first := true
	if dir != null:
		var names: Array = Array(dir.get_files())
		names.sort()
		for f in names:
			if not f.begins_with("floor_") or not f.ends_with(".map"):
				continue
			var stem: String = f.trim_prefix("floor_").trim_suffix(".map")
			if stem.is_valid_int():
				ys[stem.to_int()] = true
			var text := FileAccess.get_file_as_string(dir_path.path_join(f))
			grid_size = grid_size.max(Util.grid_extent(text))
			if first:
				title = Util.title_of(text, title)
				header_note = text.get_slice("\n", 1).strip_edges()
				if not header_note.begins_with("# ") or header_note.contains("Cell names"):
					header_note = ""
				first = false
		var rules_path := dir_path.path_join("rules.cfg")
		if FileAccess.file_exists(rules_path):
			_rules_text_loaded = FileAccess.get_file_as_string(rules_path)
	if ys.is_empty():
		ys[0] = true
		grid_size = NEW_SIZE
	var list: Array[int] = []
	for y in ys:
		list.append(y)
	list.sort()
	floors = list
	for p in plan.placements:
		p["uid"] = _next_uid
		_next_uid += 1
	_emerge_loaded = String(plan.rule("water", "emerge", ""))
	changed.emit()


## Writes every storey to `<target_root or root>/<slug>/floor_<y>.map`, removes the files of
## storeys that no longer exist, and leaves `rules.cfg` byte for byte as it was except for the
## one key the emerge-tile tool patches. A file whose text is unchanged is not touched.
func save(target_root: String = "") -> Error:
	var base := target_root if target_root != "" else root
	var dir_path := base.path_join(String(slug))
	var err := DirAccess.make_dir_recursive_absolute(dir_path)
	if err != OK:
		return err
	last_written = []
	var opts := {"title": title, "size": grid_size, "note_line": header_note}
	var wanted := {}
	for y in floors:
		var name := Writer.file_name(y)
		wanted[name] = true
		var text := Writer.write_floor(plan, y, opts)
		var path := dir_path.path_join(name)
		if FileAccess.file_exists(path) and FileAccess.get_file_as_string(path) == text:
			continue
		err = Util.write_text(path, text)
		if err != OK:
			return err
		last_written.append(name)
	var dir := DirAccess.open(dir_path)
	for f in dir.get_files():
		if f.begins_with("floor_") and f.ends_with(".map") and not wanted.has(f):
			dir.remove(f)
			last_written.append("-" + f)
	var emerge := String(plan.rule("water", "emerge", ""))
	if emerge != _emerge_loaded:
		var rules_path := dir_path.path_join("rules.cfg")
		var current := ""
		if FileAccess.file_exists(rules_path):
			current = FileAccess.get_file_as_string(rules_path)
		err = Util.write_text(rules_path, Writer.patch_emerge(current, emerge))
		if err != OK:
			return err
		last_written.append("rules.cfg")
		_emerge_loaded = emerge
	_saved_at = _undo.size()
	load_issues = []
	changed.emit()
	return OK


func _reset() -> void:
	plan = Plan.new()
	_undo.clear()
	_redo.clear()
	_saved_at = 0
	_open = null
	_depth = 0
	_next_uid = 1
	_emerge_loaded = ""
	_rules_text_loaded = ""
	load_issues = []
	last_error = ""
	last_written = []
	grid_size = NEW_SIZE
	header_note = ""
	floors = [0]


# --------------------------------------------------------------------------
# Reading
# --------------------------------------------------------------------------


## The grid the editor shows: the file's, or what the plan needs if that is more.
func extent() -> Vector2i:
	return grid_size.max(Writer.content_bounds(plan))


## What the tile is made of: floor, ice, water, wall, hole or empty. A stairs tile reads as
## `stairs`, a tile under a bridge plank as what the bridge crosses.
func terrain_of(tile: Vector3i) -> StringName:
	if plan.hole_tiles.has(tile):
		return &"hole"
	if plan.wall_tiles.has(tile):
		return &"wall"
	if plan.pit_tiles.has(tile):
		return &"water" if plan.water_tiles.has(tile) else &"empty"
	if plan.water_tiles.has(tile):
		return &"water"
	if plan.floor_tiles.has(tile):
		return &"ice" if plan.tile_props.get(tile, {}).get("surface", "") == "ice" else &"floor"
	return &"empty"


func placements_at(tile: Vector3i) -> Array:
	return plan.placements_at(tile)


## The placement with this uid, or {}.
func placement(uid: int) -> Dictionary:
	for p in plan.placements:
		if p["uid"] == uid:
			return p
	return {}


## The properties of a bare tile (never the grid's own `surface`), a copy.
func tile_props(tile: Vector3i) -> Dictionary:
	var props: Dictionary = plan.tile_props.get(tile, {}).duplicate(true)
	props.erase("surface")
	return props


## The names of the zones holding `tile`.
func zones_at(tile: Vector3i) -> Array[String]:
	var out: Array[String] = []
	for name in plan.zones:
		if plan.zones[name]["tiles"].has(tile):
			out.append(String(name))
	out.sort()
	return out


func emerge_tile():
	var text := String(plan.rule("water", "emerge", ""))
	return Kinds.parse_tile(text, 0) if text != "" else null


## The issues the validator finds in the working plan, with what the parser said at load.
func validate() -> Array:
	var saved: Array = plan.issues
	plan.issues = load_issues.duplicate()
	var issues: Array = Validator.new().validate(plan, GameData.dungeon(slug))
	plan.issues = saved
	return issues


# --------------------------------------------------------------------------
# Terrain
# --------------------------------------------------------------------------


## Paints `terrain` (one of [constant TERRAINS]) on every tile of `tiles` — one command. What
## cannot stand on the new terrain goes: painting a wall removes the trap on it, painting floor
## removes the stairs on it. Gates, rails and scenery stay.
func paint(tiles: Array, terrain: StringName) -> bool:
	if not TERRAINS.has(terrain):
		return _refuse("UNKNOWN_TERRAIN")
	begin("paint")
	var drop := {}
	for tile in tiles:
		if tile.x < 0 or tile.z < 0:
			continue
		_paint_tile(tile, terrain, drop)
	_drop_placements(drop)
	commit()
	last_error = ""
	return true


## Paints the rectangle between two tiles of one storey.
func paint_rect(a: Vector3i, b: Vector3i, terrain: StringName) -> bool:
	return paint(Util.rect_tiles(a, b), terrain)


func _paint_tile(tile: Vector3i, terrain: StringName, drop: Dictionary) -> void:
	_clear_terrain(tile)
	var walkable := terrain == &"floor" or terrain == &"ice"
	match terrain:
		&"floor":
			_put(plan.floor_tiles, tile, true)
		&"ice":
			_put(plan.floor_tiles, tile, true)
			_set_tile_prop_raw(tile, "surface", "ice")
		&"water":
			_put(plan.water_tiles, tile, true)
		&"wall":
			_put(plan.wall_tiles, tile, true)
		&"hole":
			_put(plan.hole_tiles, tile, true)
	for p in plan.placements_at(tile):
		var floor_rule: String = (
			Kinds.KINDS[p["kind"]]["floor"] if Kinds.has_kind(p["kind"]) else ""
		)
		if walkable and (floor_rule == "no" or p["kind"] == &"bridge"):
			drop[p["uid"]] = true
		elif not walkable and floor_rule != "any":
			if not (terrain == &"wall" and p["kind"] == &"cracked_wall"):
				drop[p["uid"]] = true
	if not walkable:
		_unmark(tile)


## Removes the entrance and exit marks of a tile that stopped being walkable.
func _unmark(tile: Vector3i) -> void:
	if plan.has_entrance and plan.entrance == tile:
		_field(plan, "has_entrance", false)
	if plan.exits.has(tile):
		var exits: Array[Vector3i] = plan.exits.duplicate()
		exits.erase(tile)
		_field(plan, "exits", exits)


## Takes the tile's terrain flags off: floor, hole, pit, wall, water, and the ice surface.
func _clear_terrain(tile: Vector3i) -> void:
	for dict in [
		plan.floor_tiles, plan.hole_tiles, plan.pit_tiles, plan.wall_tiles, plan.water_tiles
	]:
		_erase(dict, tile)
	_set_tile_prop_raw(tile, "surface", null)


## Makes a tile walkable for something that needs floor: what stood in the way (wall, hole, water,
## stairs) goes, a bridge's pit stays.
func _make_walkable(tile: Vector3i, drop: Dictionary) -> void:
	if plan.floor_tiles.has(tile):
		return
	for dict in [plan.hole_tiles, plan.wall_tiles, plan.water_tiles, plan.pit_tiles]:
		_erase(dict, tile)
	_put(plan.floor_tiles, tile, true)
	for p in plan.placements_at(tile):
		if Kinds.KINDS.get(p["kind"], {}).get("floor", "") == "no":
			drop[p["uid"]] = true


# --------------------------------------------------------------------------
# Placements
# --------------------------------------------------------------------------


## Places a `kind` on `tile` with `props` (typed values, checked against the kinds table).
## Returns its uid, or -1 and `last_error`.
func place(kind: StringName, tile: Vector3i, props: Dictionary = {}) -> int:
	if not Kinds.has_kind(kind):
		_refuse("UNKNOWN_KIND")
		return -1
	if tile.x < 0 or tile.z < 0:
		_refuse("OUT_OF_GRID")
		return -1
	var bad := Util.check_props(kind, props)
	if bad != "":
		_refuse("BAD_PROP:" + bad)
		return -1
	begin("place")
	var drop := {}
	_apply_kind(kind, tile, props, drop)
	var uid := _next_uid
	_next_uid += 1
	var list: Array = plan.placements.duplicate()
	list.append(
		{"kind": kind, "tile": tile, "props": props.duplicate(true), "source": "", "uid": uid}
	)
	_set_placements(list)
	_drop_placements(drop, uid)
	commit()
	last_error = ""
	return uid


## The terrain a kind leaves on its tile, as the parser does when it reads the kind.
func _apply_kind(kind: StringName, tile: Vector3i, props: Dictionary, drop: Dictionary) -> void:
	var def: Dictionary = Kinds.KINDS[kind]
	if kind == &"bridge":
		_clear_terrain(tile)
		_put(plan.floor_tiles, tile, true)
		_put(plan.pit_tiles, tile, true)
		if props.get("over", "void") == "water":
			_put(plan.water_tiles, tile, true)
		_unmark_stairs_here(tile, drop)
		return
	if kind == &"cracked_wall":
		_clear_terrain(tile)
		_put(plan.wall_tiles, tile, true)
		_unmark(tile)
		_drop_floor_things(tile, drop)
		return
	match def["floor"]:
		"yes":
			_make_walkable(tile, drop)
		"no":
			_clear_terrain(tile)
			_unmark(tile)
			_drop_floor_things(tile, drop)


func _unmark_stairs_here(tile: Vector3i, drop: Dictionary) -> void:
	for p in plan.placements_at(tile):
		if Kinds.KINDS.get(p["kind"], {}).get("floor", "") == "no":
			drop[p["uid"]] = true


## Everything on the tile that needs floor goes (stairs and cracked walls come in without it).
func _drop_floor_things(tile: Vector3i, drop: Dictionary) -> void:
	for p in plan.placements_at(tile):
		if Kinds.KINDS.get(p["kind"], {}).get("floor", "") == "yes":
			drop[p["uid"]] = true


## Replaces every property of a placement. The terrain follows (a bridge `over` water or void).
func edit_placement(uid: int, props: Dictionary) -> bool:
	var p := placement(uid)
	if p.is_empty():
		return _refuse("NO_SUCH_PLACEMENT")
	var bad := Util.check_props(p["kind"], props)
	if bad != "":
		return _refuse("BAD_PROP:" + bad)
	begin("edit")
	var list: Array = []
	for q in plan.placements:
		if q["uid"] == uid:
			list.append(
				{
					"kind": q["kind"],
					"tile": q["tile"],
					"props": props.duplicate(true),
					"source": q["source"],
					"uid": uid
				}
			)
		else:
			list.append(q)
	_set_placements(list)
	if p["kind"] == &"bridge":
		if props.get("over", "void") == "water":
			_put(plan.water_tiles, p["tile"], true)
		else:
			_erase(plan.water_tiles, p["tile"])
	commit()
	last_error = ""
	return true


## Removes a placement. What it leaves behind: a bridge, the water or the void it crossed;
## stairs and a cracked wall, floor and wall.
func remove_placement(uid: int, with_partner: bool = false) -> bool:
	var p := placement(uid)
	if p.is_empty():
		return _refuse("NO_SUCH_PLACEMENT")
	begin("remove")
	var partner := {}
	if with_partner and p["kind"] == &"stairs":
		partner = stairs_partner(p["tile"], p["props"])
	_remove_one(p)
	if not partner.is_empty():
		for q in plan.placements_at(partner["tile"]).duplicate():
			if q["kind"] == &"stairs":
				_remove_one(q)
	commit()
	last_error = ""
	return true


func _remove_one(p: Dictionary) -> void:
	var tile: Vector3i = p["tile"]
	var list: Array = []
	for q in plan.placements:
		if q["uid"] != p["uid"]:
			list.append(q)
	_set_placements(list)
	match p["kind"]:
		&"bridge":
			_erase(plan.floor_tiles, tile)
			_erase(plan.pit_tiles, tile)
		&"stairs":
			_put(plan.floor_tiles, tile, true)


## The placements of `drop` (a set of uids) leave; `keep` is never one of them.
func _drop_placements(drop: Dictionary, keep: int = -1) -> void:
	if drop.is_empty():
		return
	var list: Array = []
	var changed_any := false
	for q in plan.placements:
		if drop.has(q["uid"]) and q["uid"] != keep:
			changed_any = true
		else:
			list.append(q)
	if changed_any:
		_set_placements(list)


## Stairs `direction` ("up" climbs, "down" descends) facing `face` (N, E, S, W) on `tile`. With
## `with_partner` the matching flight goes on the next storey in the same cell, if that storey
## exists: a flight that climbs north meets, above, one that descends south. Its uid is
## `last_partner_uid`, -1 when there was none to place.
func place_stairs(
	tile: Vector3i, direction: String, face: String, with_partner: bool = true
) -> int:
	last_partner_uid = -1
	var props := {"dir": direction, "face": Kinds.DIRECTIONS.get(face, Vector3i.ZERO)}
	if not Kinds.DIRECTIONS.has(face) or not ["up", "down"].has(direction):
		_refuse("BAD_PROP:dir")
		return -1
	begin("stairs")
	_remove_stairs_at(tile)
	var uid := place(&"stairs", tile, props)
	if uid >= 0 and with_partner:
		var partner := stairs_partner(tile, props)
		if not partner.is_empty():
			_remove_stairs_at(partner["tile"])
			last_partner_uid = place(&"stairs", partner["tile"], partner["props"])
	commit()
	return uid


func _remove_stairs_at(tile: Vector3i) -> void:
	for q in plan.placements_at(tile).duplicate():
		if q["kind"] == &"stairs":
			_remove_one(q)


## Where the other end of a flight lies: {tile, props} for the storey above (a flight that climbs)
## or below (one that descends), or {} when that storey does not exist.
func stairs_partner(tile: Vector3i, props: Dictionary) -> Dictionary:
	var up: bool = props.get("dir", "") == "up"
	var y := tile.y + (1 if up else -1)
	if not floors.has(y) or not props.has("face"):
		return {}
	var opposite: Vector3i = -props["face"]
	return {
		"tile": Vector3i(tile.x, y, tile.z),
		"props": {"dir": "down" if up else "up", "face": opposite},
	}


# --------------------------------------------------------------------------
# Entrance and exits, tile properties
# --------------------------------------------------------------------------


## The entrance, on `tile` (made floor), looking `facing` and leaving across `exit_edge`.
func set_entrance(tile: Vector3i, facing: String = "", exit_edge: String = "") -> bool:
	if tile.x < 0 or tile.z < 0:
		return _refuse("OUT_OF_GRID")
	begin("entrance")
	var drop := {}
	_make_walkable(tile, drop)
	_drop_placements(drop)
	_field(plan, "entrance", tile)
	_field(plan, "has_entrance", true)
	_set_dir_props(tile, facing, exit_edge)
	commit()
	last_error = ""
	return true


func clear_entrance() -> bool:
	if not plan.has_entrance:
		return false
	begin("entrance")
	_field(plan, "has_entrance", false)
	commit()
	return true


func add_exit(tile: Vector3i, exit_edge: String = "") -> bool:
	if tile.x < 0 or tile.z < 0:
		return _refuse("OUT_OF_GRID")
	begin("exit")
	var drop := {}
	_make_walkable(tile, drop)
	_drop_placements(drop)
	if not plan.exits.has(tile):
		var exits: Array[Vector3i] = plan.exits.duplicate()
		exits.append(tile)
		_field(plan, "exits", exits)
	_set_dir_props(tile, "", exit_edge)
	commit()
	last_error = ""
	return true


func remove_exit(tile: Vector3i) -> bool:
	if not plan.exits.has(tile):
		return _refuse("NO_SUCH_EXIT")
	begin("exit")
	var exits: Array[Vector3i] = plan.exits.duplicate()
	exits.erase(tile)
	_field(plan, "exits", exits)
	commit()
	return true


func _set_dir_props(tile: Vector3i, facing: String, exit_edge: String) -> void:
	if facing != "":
		_set_tile_prop_raw(tile, "facing", Kinds.DIRECTIONS[facing])
	if exit_edge != "":
		_set_tile_prop_raw(tile, "exit_edge", Kinds.DIRECTIONS[exit_edge])


## Sets one property of a bare tile (`note`, `tags`, `asset`, `facing`, `exit_edge`, or
## `custom.<name>`); null, "" or an empty list removes it.
func set_tile_prop(tile: Vector3i, name: String, value) -> bool:
	if tile.x < 0 or tile.z < 0:
		return _refuse("OUT_OF_GRID")
	var type: String = Kinds.COMMON.get(name, "str" if name.begins_with("custom.") else "")
	if type == "":
		return _refuse("BAD_PROP:" + name)
	if value is String and type == "dir" and value != "":
		value = Kinds.DIRECTIONS.get(value)
	var empty: bool = value == null or (value is String and value == "")
	empty = empty or (value is Array and value.is_empty())
	if not empty and not Util.value_ok(type, value):
		return _refuse("BAD_PROP:" + name)
	begin("tile")
	_set_tile_prop_raw(tile, name, null if empty else value)
	commit()
	last_error = ""
	return true


func _set_tile_prop_raw(tile: Vector3i, name: String, value) -> void:
	if value == null and not plan.tile_props.get(tile, {}).has(name):
		return
	var props: Dictionary = plan.tile_props.get(tile, {}).duplicate(true)
	if value == null:
		props.erase(name)
	else:
		props[name] = value
	if props.is_empty():
		_erase(plan.tile_props, tile)
	else:
		_put(plan.tile_props, tile, props)


# --------------------------------------------------------------------------
# Zones
# --------------------------------------------------------------------------


func create_zone(name: String, tags: Array = []) -> bool:
	if not Util.valid_zone_name(name):
		return _refuse("BAD_ZONE_NAME")
	if plan.zones.has(name):
		return _refuse("ZONE_EXISTS")
	begin("zone")
	_put(plan.zones, name, {"tags": tags.duplicate(), "tiles": {}, "props": {}})
	commit()
	last_error = ""
	return true


func delete_zone(name: String) -> bool:
	if not plan.zones.has(name):
		return _refuse("NO_SUCH_ZONE")
	begin("zone")
	_erase(plan.zones, name)
	commit()
	return true


## Replaces the tags of a zone (an empty list for none).
func set_zone_tags(name: String, tags: Array) -> bool:
	if not plan.zones.has(name):
		return _refuse("NO_SUCH_ZONE")
	begin("zone")
	_log_dict(plan.zones, name)
	plan.zones[name]["tags"] = tags.duplicate()
	commit()
	return true


## Sets a zone's `note` or `custom.<name>`; "" removes it.
func set_zone_prop(name: String, key: String, value: String) -> bool:
	if not plan.zones.has(name):
		return _refuse("NO_SUCH_ZONE")
	if key != "note" and not key.begins_with("custom."):
		return _refuse("BAD_PROP:" + key)
	if value.contains('"'):
		return _refuse("BAD_PROP:" + key)
	begin("zone")
	_log_dict(plan.zones, name)
	if value == "":
		plan.zones[name]["props"].erase(key)
	else:
		plan.zones[name]["props"][key] = value
	commit()
	return true


func zone_paint(name: String, tiles: Array) -> bool:
	return _zone_tiles(name, tiles, true)


func zone_erase(name: String, tiles: Array) -> bool:
	return _zone_tiles(name, tiles, false)


func _zone_tiles(name: String, tiles: Array, add: bool) -> bool:
	if not plan.zones.has(name):
		return _refuse("NO_SUCH_ZONE")
	begin("zone")
	_log_dict(plan.zones, name)
	for tile in tiles:
		if add and tile.x >= 0 and tile.z >= 0:
			plan.zones[name]["tiles"][tile] = true
		elif not add:
			plan.zones[name]["tiles"].erase(tile)
	commit()
	last_error = ""
	return true


# --------------------------------------------------------------------------
# Storeys, rules
# --------------------------------------------------------------------------


## Adds the storey `y` (the one above the top by default). False when it exists.
func add_floor(y: int = 1 << 30) -> bool:
	if y == 1 << 30:
		y = floors[-1] + 1
	if floors.has(y):
		return _refuse("FLOOR_EXISTS")
	begin("floor")
	var list: Array[int] = floors.duplicate()
	list.append(y)
	list.sort()
	_field(self, "floors", list)
	commit()
	last_error = ""
	return true


## Deletes a storey and everything on it. Never the last one.
func delete_floor(y: int) -> bool:
	if not floors.has(y) or floors.size() == 1:
		return _refuse("NO_SUCH_FLOOR")
	begin("floor")
	for dict in [
		plan.floor_tiles,
		plan.hole_tiles,
		plan.pit_tiles,
		plan.wall_tiles,
		plan.water_tiles,
		plan.tile_props
	]:
		for tile in dict.keys():
			if tile.y == y:
				_erase(dict, tile)
	var drop := {}
	for p in plan.placements:
		if p["tile"].y == y:
			drop[p["uid"]] = true
	_drop_placements(drop)
	for name in plan.zones.keys():
		var doomed: Array = []
		for tile in plan.zones[name]["tiles"]:
			if tile.y == y:
				doomed.append(tile)
		if not doomed.is_empty():
			_zone_tiles(name, doomed, false)
	if plan.has_entrance and plan.entrance.y == y:
		_field(plan, "has_entrance", false)
	var exits: Array[Vector3i] = []
	for tile in plan.exits:
		if tile.y != y:
			exits.append(tile)
	if exits.size() != plan.exits.size():
		_field(plan, "exits", exits)
	var list: Array[int] = floors.duplicate()
	list.erase(y)
	_field(self, "floors", list)
	commit()
	last_error = ""
	return true


## The tile the player comes up on after falling into water: patches `[water] emerge` in
## `rules.cfg` at the next save, and nothing else in that file.
func set_emerge(tile: Vector3i) -> bool:
	if tile.x < 0 or tile.z < 0:
		return _refuse("OUT_OF_GRID")
	begin("emerge")
	_log_dict(plan.rules, "water")
	if not plan.rules.has("water"):
		plan.rules["water"] = {}
	plan.rules["water"]["emerge"] = "%s@%d" % [Writer.cell_name(tile.x, tile.z), tile.y]
	commit()
	last_error = ""
	return true


func _refuse(code: String) -> bool:
	last_error = code
	return false

# --------------------------------------------------------------------------
# Comparing plans
# --------------------------------------------------------------------------
