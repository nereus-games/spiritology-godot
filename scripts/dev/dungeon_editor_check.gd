## Headless check of the dungeon editor's two logic layers: the map writer and the model with
## its undo stack. The screen has its own, `dungeon_editor_gui_check`.
##
## The writer's promises are that its text parses back to the same plan and that writing is a
## fixed point; the model's, that every operation is one command and that undo and redo put the
## plan back EXACTLY (`canonical` says what exactly means). Nothing here writes into `data/`:
## saves go to a temporary directory.
##
## Run with: Godot --headless --path . res://scenes/dev/dungeon_editor_check.tscn
## As a start scene rather than --script; see geometry_check.gd.
extends Node

const Kinds := preload("res://scripts/dungeon/dungeon_kinds.gd")
const Plan := preload("res://scripts/dungeon/dungeon_plan.gd")
const Parser := preload("res://scripts/dungeon/dungeon_map_parser.gd")
const Writer := preload("res://scripts/dungeon/dungeon_map_writer.gd")
const Model := preload("res://scripts/dungeon/editor/dungeon_editor_model.gd")
const Util := preload("res://scripts/dungeon/editor/dungeon_editor_util.gd")

const LAKE := &"norgzevod_frozen_lake"
const TEMP := "user://dungeon_editor_check/"

var _fails: Array[String] = []


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  OK   %s" % label)
	else:
		print("  FAIL %s" % label)
		_fails.append(label)


func _ready() -> void:
	await get_tree().process_frame
	_clean_temp()
	_check_writer_helpers()
	_check_writer_inline()
	_check_writer_lake()
	_check_terrain()
	_check_placements()
	_check_stairs()
	_check_entrance_and_exits()
	_check_tile_props()
	_check_zones()
	_check_floors()
	_check_grouping_and_dirty()
	_check_validation()
	_check_save_and_load()
	_check_emerge()
	_clean_temp()
	print("")
	if _fails.is_empty():
		print("ALL OK")
	else:
		print("FAILURES: %s" % [_fails])
	get_tree().quit(0 if _fails.is_empty() else 1)


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------


## Everything an undo has to put back: the plan, the storeys, the emerge tile.
func _state(m: Model) -> String:
	var zones := []
	for name in m.plan.zones:
		zones.append([name, m.plan.zones[name]["tags"], m.plan.zones[name]["props"]])
	return (
		"%s\n%s\n%s\n%s"
		% [Util.canonical(m.plan), str(m.floors), m.plan.rule("water", "emerge", ""), str(zones)]
	)


## Runs `op`, then checks that it changed something, that undo restores the state exactly and
## that redo brings the result back exactly.
func _undoable(m: Model, label: String, op: Callable) -> void:
	var before := _state(m)
	var depth: int = m._undo.size()
	op.call()
	var after := _state(m)
	_check(after != before, "%s: it changes the plan" % label)
	_check(m._undo.size() == depth + 1, "%s: it is one command" % label)
	_check(m.dirty, "%s: it makes the model dirty" % label)
	_check(m.undo(), "%s: undo" % label)
	_check(_state(m) == before, "%s: undo restores the plan exactly" % label)
	_check(m.redo(), "%s: redo" % label)
	_check(_state(m) == after, "%s: redo brings the result back exactly" % label)


func _parse_texts(texts: Dictionary, slug: StringName = &"t") -> Plan:
	var plan := Plan.new()
	plan.slug = slug
	var ys: Array = texts.keys()
	ys.sort()
	for y in ys:
		Parser.new().read_floor(plan, texts[y], "t/floor_%d.map" % y)
	return plan


func _sample(type: String, y: int):
	if type.begins_with("enum:"):
		return type.substr(5).split("|")[0]
	match type:
		"bool":
			return true
		"int":
			return 3
		"float":
			return 1.5
		"str":
			return "a b"
		"list":
			return ["x", "y"]
		"dir":
			return Kinds.DIRECTIONS["E"]
		"tile":
			return Vector3i(2, y, 3)
		"tiles":
			return [Vector3i(2, y, 3), Vector3i(4, y + 1, 5)]
	return null


func _sample_props(kind: StringName, y: int) -> Dictionary:
	var out := {}
	for name in Kinds.KINDS[kind]["props"]:
		out[name] = _sample(Kinds.KINDS[kind]["props"][name], y)
	return out


## A small dungeon that uses everything the format has.
func _inline_model() -> Model:
	var m := Model.new()
	m.new_dungeon(&"t", TEMP)
	m.add_floor(1)
	m.paint_rect(Vector3i(0, 0, 0), Vector3i(20, 0, 12), &"floor")
	m.paint_rect(Vector3i(5, 0, 5), Vector3i(7, 0, 6), &"ice")
	m.paint_rect(Vector3i(10, 0, 5), Vector3i(11, 0, 6), &"water")
	m.paint_rect(Vector3i(13, 0, 5), Vector3i(14, 0, 6), &"wall")
	m.paint_rect(Vector3i(16, 0, 5), Vector3i(16, 0, 6), &"hole")
	m.paint_rect(Vector3i(0, 1, 0), Vector3i(20, 1, 12), &"floor")
	m.set_entrance(Vector3i(1, 0, 1), "S", "W")
	m.add_exit(Vector3i(19, 0, 11), "E")
	var x := 0
	for kind in Kinds.KINDS:
		if kind == &"stairs":
			continue
		var props := _sample_props(kind, 0)
		props["note"] = "n %d" % x
		var tile := Vector3i(2 + x % 16, 0, 8 + floori(x / 16.0))
		m.place(kind, tile, props)
		x += 1
	m.place_stairs(Vector3i(3, 0, 10), "up", "N")
	m.place_stairs(Vector3i(5, 1, 10), "down", "W", false)
	m.place(&"bridge", Vector3i(10, 0, 2), {"over": "water"})
	m.place(&"bridge", Vector3i(11, 0, 2), {"over": "void"})
	m.set_tile_prop(Vector3i(2, 0, 2), "note", "free note")
	m.set_tile_prop(Vector3i(2, 0, 2), "tags", ["unreachable_ok", "q"])
	m.set_tile_prop(Vector3i(5, 0, 5), "note", "a note on ice")
	m.set_tile_prop(Vector3i(3, 0, 2), "custom.thing", "x")
	m.create_zone("hall", ["safe", "no_teleport"])
	m.zone_paint("hall", Util.rect_tiles(Vector3i(2, 0, 2), Vector3i(4, 0, 3)))
	m.zone_paint("hall", [Vector3i(9, 0, 9), Vector3i(10, 1, 9), Vector3i(10, 1, 10)])
	m.set_zone_prop("hall", "note", "the safe hall")
	m.create_zone("odd")
	m.zone_paint("odd", [Vector3i(0, 0, 12), Vector3i(1, 0, 12), Vector3i(1, 0, 11)])
	m.zone_paint("odd", [Vector3i(0, 1, 0), Vector3i(0, 1, 1)])
	return m


# --------------------------------------------------------------------------
# The writer
# --------------------------------------------------------------------------


func _check_writer_helpers() -> void:
	print("-- writer helpers")
	_check(Writer.cell_name(0, 0) == "A1", "cell A1")
	_check(Writer.cell_name(25, 8) == "Z9", "cell Z9")
	_check(Writer.cell_name(26, 0) == "AA1", "cell AA1")
	_check(Writer.cell_name(27, 23) == "AB24", "cell AB24")
	_check(Writer.cell_name(701, 0) == "ZZ1", "cell ZZ1")
	_check(Writer.cell_name(702, 0) == "AAA1", "cell AAA1")
	for x in [0, 1, 25, 26, 27, 51, 52, 700, 701, 702, 1000]:
		_check(
			Kinds.cell_tile(Writer.cell_name(x, 4)) == Vector2i(x, 4), "cell name %d reads back" % x
		)
	_check(Writer.tile_ref(Vector3i(0, 0, 0), 0) == "A1", "a tile of the file's storey")
	_check(Writer.tile_ref(Vector3i(1, -2, 1), 0) == "B2@-2", "a tile of another storey")
	_check(Writer.dir_letter(Vector3i(0, 0, -1)) == "N", "north is -z")
	_check(Writer.dir_letter(Vector3i(1, 1, 1)) == "", "not a direction")
	var up := {"kind": &"stairs", "props": {"dir": "up", "face": Vector3i(1, 0, 0)}}
	var down := {"kind": &"stairs", "props": {"dir": "down", "face": Vector3i(0, 0, 1)}}
	var noted := {"kind": &"stairs", "props": {"dir": "up", "face": Vector3i(0, 0, 1), "note": "x"}}
	_check(Writer.stairs_char(up) == ">", "stairs that climb east are >")
	_check(Writer.stairs_char(down) == "s", "stairs that descend south are s")
	_check(Writer.stairs_char(noted) == "", "stairs with a note go to [tiles]")
	var rules := '[a]\nx=1\n\n[water]\nemerge="F25@0"\n; keep\n[b]\ny=2\n'
	_check(
		Writer.patch_emerge(rules, "A1@2") == rules.replace('"F25@0"', '"A1@2"'),
		"the emerge line is replaced and nothing else"
	)
	_check(
		Writer.patch_emerge("[water]\nfoo=1\n", "A1@0") == '[water]\nemerge="A1@0"\nfoo=1\n',
		"the key is added under an existing [water]"
	)
	_check(
		Writer.patch_emerge("[a]\nx=1\n", "A1@0") == '[a]\nx=1\n\n[water]\nemerge="A1@0"\n',
		"a [water] section is appended when there is none"
	)
	var cfg := ConfigFile.new()
	_check(
		cfg.parse(Writer.patch_emerge(rules, "A1@2")) == OK, "the patched rules.cfg still parses"
	)


func _check_writer_inline() -> void:
	print("-- writer on a plan that uses everything")
	var m := _inline_model()
	var opts := {"title": "Inline"}
	var texts := Writer.write_all(m.plan, m.floors, opts)
	_check(texts.size() == 2, "one text per storey")
	var plan2 := _parse_texts(texts)
	_check(plan2.issues.is_empty(), "the text parses without an issue: %s" % [plan2.issues])
	_check(Util.canonical(plan2) == Util.canonical(m.plan), "write then parse: the same plan")
	var texts2 := Writer.write_all(plan2, m.floors, opts)
	_check(texts2 == texts, "write(parse(write(plan))) == write(plan)")
	var plan3 := _parse_texts(texts2)
	_check(Util.canonical(plan3) == Util.canonical(m.plan), "...and once more")
	var text: String = texts[0]
	_check(text.contains("[legend]") and text.contains("^ = stairs dir=up face=N"), "a legend")
	_check(
		text.contains("\n^") or text.contains("^\n") or text.contains("^."), "stairs in the grid"
	)
	_check(text.contains("# trap\n"), "tiles are grouped under a heading")
	_check(text.contains('note="a b"'.replace("a b", "n 0")), "values with a space are quoted")
	_check(text.ends_with("\n") and not text.ends_with("\n\n"), "one newline ends the file")
	# The stairs of the second storey went to [tiles] or the grid, and the paired flight arrived.
	_check(texts[1].contains("s = stairs dir=down face=S"), "the partner flight descends south")
	# A wider grid is asked for and respected.
	var wide := Writer.write_floor(m.plan, 0, {"size": Vector2i(40, 30)})
	var rows := wide.split("[grid]\n")[1].split("\n\n")[0].split("\n")
	_check(rows.size() == 30 and rows[0].length() == 40, "a requested size is written")
	var plan4 := _parse_texts({0: wide})
	_check(plan4.floor_tiles.size() == _count_y(m.plan.floor_tiles, 0), "...and reads back")
	# An empty storey is still a file that parses.
	var empty := Plan.new()
	var blank := Writer.write_floor(empty, 3)
	var plan5 := _parse_texts({3: blank})
	_check(plan5.issues.is_empty() and plan5.floor_tiles.is_empty(), "an empty storey is valid")
	# Properties that the table does not know survive.
	var odd := Plan.new()
	odd.slug = &"odd"
	var v := Vector3i(1, 0, 1)
	odd.floor_tiles[v] = true
	odd.add_placement(&"chest", v, {"trapped": true, "weird": "yes", "custom.k": "1 2"}, "")
	var back := _parse_texts({0: Writer.write_floor(odd, 0)})
	_check(Util.canonical(back) == Util.canonical(odd), "unknown and custom properties survive")


func _count_y(dict: Dictionary, y: int) -> int:
	var n := 0
	for tile in dict:
		if tile.y == y:
			n += 1
	return n


func _check_writer_lake() -> void:
	print("-- writer on the frozen lake")
	var m := Model.new()
	m.load_dungeon(LAKE)
	_check(m.floors == [-2, -1, 0, 1, 2], "five storeys")
	_check(m.grid_size == Vector2i(31, 39), "31 x 39")
	var opts := {"title": m.title, "size": m.grid_size, "note_line": m.header_note}
	var texts := Writer.write_all(m.plan, m.floors, opts)
	var plan2 := _parse_texts(texts, LAKE)
	_check(plan2.issues.is_empty(), "the lake's text parses cleanly")
	_check(Util.canonical(plan2) == Util.canonical(m.plan), "the lake: write then parse, same plan")
	_check(Writer.write_all(plan2, m.floors, opts) == texts, "the lake: writing is a fixed point")
	# The committed files are the writer's own output: saving an unedited lake changes nothing.
	for y in m.floors:
		var committed := FileAccess.get_file_as_string(
			"res://data/dungeons/%s/%s" % [LAKE, Writer.file_name(y)]
		)
		_check(texts[y] == committed, "floor %d: the committed file is what the writer gives" % y)
	_check(m.title.begins_with("Norgz"), "the title is kept from the files' header")


# --------------------------------------------------------------------------
# The model
# --------------------------------------------------------------------------


func _fresh() -> Model:
	var m := Model.new()
	m.new_dungeon(&"t", TEMP)
	m.paint_rect(Vector3i(0, 0, 0), Vector3i(9, 0, 9), &"floor")
	m._undo.clear()
	m._saved_at = 0
	return m


func _check_terrain() -> void:
	print("-- terrain")
	var m := _fresh()
	var t := Vector3i(2, 0, 2)
	for terrain in [&"ice", &"water", &"wall", &"hole", &"empty"]:
		_undoable(m, "paint %s" % terrain, func(): m.paint([t], terrain))
		m.paint([t], terrain)
		_check(m.terrain_of(t) == terrain, "the tile reads back as %s" % terrain)
		m.paint([t], &"floor")
	_undoable(
		m, "paint a rectangle", func(): m.paint_rect(Vector3i(3, 0, 3), Vector3i(6, 0, 5), &"wall")
	)
	m.paint_rect(Vector3i(3, 0, 3), Vector3i(6, 0, 5), &"wall")
	_check(
		m.terrain_of(Vector3i(6, 0, 5)) == &"wall" and m.terrain_of(Vector3i(7, 0, 5)) == &"floor",
		"a rectangle is inclusive"
	)
	_check(not m.paint([t], &"lava") and m.last_error == "UNKNOWN_TERRAIN", "an unknown terrain")
	m.paint([Vector3i(-1, 0, 0)], &"wall")
	_check(not m.plan.wall_tiles.has(Vector3i(-1, 0, 0)), "nothing is painted at a negative tile")
	# What cannot stand on the new terrain goes with it.
	var trap := m.place(&"trap", Vector3i(1, 0, 1), {"type": "poison"})
	var gate := m.place(
		&"gate", Vector3i(1, 0, 1), {"type": "automated", "edge": Kinds.DIRECTIONS["N"]}
	)
	m.paint([Vector3i(1, 0, 1)], &"wall")
	_check(m.placement(trap).is_empty(), "painting a wall removes the trap")
	_check(not m.placement(gate).is_empty(), "...and leaves the gate")
	m.undo()
	_check(not m.placement(trap).is_empty(), "undo brings the trap back")
	m.redo()
	m.paint([Vector3i(1, 0, 1)], &"floor")
	var stairs := m.place_stairs(Vector3i(8, 0, 8), "up", "N", false)
	m.paint([Vector3i(8, 0, 8)], &"floor")
	_check(m.placement(stairs).is_empty(), "painting floor removes the stairs")
	m.set_entrance(Vector3i(9, 0, 9), "N", "S")
	m.paint([Vector3i(9, 0, 9)], &"water")
	_check(not m.plan.has_entrance, "painting water under the entrance removes it")
	m.add_exit(Vector3i(0, 0, 9), "W")
	m.paint([Vector3i(0, 0, 9)], &"wall")
	_check(m.plan.exits.is_empty(), "painting a wall under an exit removes it")


func _check_placements() -> void:
	print("-- placements")
	var m := _fresh()
	var n := 0
	for kind in Kinds.KINDS:
		if kind == &"stairs":
			continue
		var tile := Vector3i(n % 10, 0, floori(n / 10.0))
		var props := _sample_props(kind, 0)
		var box := [-1]
		_undoable(m, "place %s" % kind, func(): box[0] = m.place(kind, tile, props))
		var uid: int = box[0]
		_check(uid >= 0, "%s: placed" % kind)
		var floor_rule: String = Kinds.KINDS[kind]["floor"]
		if floor_rule == "yes":
			_check(m.plan.floor_tiles.has(tile), "%s makes its tile floor" % kind)
		if kind == &"cracked_wall":
			_check(
				m.plan.wall_tiles.has(tile) and not m.plan.floor_tiles.has(tile),
				"a cracked wall is wall"
			)
		n += 1
	var tile := Vector3i(2, 0, 7)
	_check(m.place(&"nonsense", tile) == -1 and m.last_error == "UNKNOWN_KIND", "an unknown kind")
	_check(m.place(&"trap", tile, {"type": "lava"}) == -1, "an enum value outside the table")
	_check(m.last_error == "BAD_PROP:type", "...and says which property")
	_check(m.place(&"trap", tile, {"poison_turns": "three"}) == -1, "an int that is not one")
	_check(m.place(&"trap", tile, {"bogus": 1}) == -1, "a property the kind does not have")
	_check(
		m.place(&"trap", tile, {"custom.x": "ok", "note": "n"}) >= 0, "custom and common ones pass"
	)
	_check(m.place(&"trap", Vector3i(-1, 0, 0)) == -1, "no tile at a negative coordinate")
	# A bridge is a floor over a pit, over water when it says so; removing it takes that back.
	var b := m.place(&"bridge", Vector3i(7, 0, 7), {"over": "water"})
	_check(
		m.plan.pit_tiles.has(Vector3i(7, 0, 7)) and m.plan.water_tiles.has(Vector3i(7, 0, 7)),
		"a bridge over water"
	)
	_undoable(m, "edit a bridge", func(): m.edit_placement(b, {"over": "void"}))
	_check(not m.plan.water_tiles.has(Vector3i(7, 0, 7)), "...over void instead: no water")
	_undoable(m, "remove a bridge", func(): m.remove_placement(b))
	_check(m.terrain_of(Vector3i(7, 0, 7)) == &"empty", "a bridge over void leaves the void")
	# Edit and remove an ordinary one.
	var c := m.place(&"chest", Vector3i(5, 0, 5), {"trapped": false})
	_undoable(m, "edit a chest", func(): m.edit_placement(c, {"trapped": true, "loot": ["a"]}))
	_check(m.placement(c)["props"]["loot"] == ["a"], "the edit is in the plan")
	_check(not m.edit_placement(c, {"trapped": "yes"}), "an edit that does not fit is refused")
	_check(m.placement(c)["props"]["trapped"] == true, "...and changes nothing")
	_undoable(m, "remove a chest", func(): m.remove_placement(c))
	_check(not m.remove_placement(9999), "removing what is not there")
	# Placement uids survive an undo.
	m.undo()
	_check(not m.placement(c).is_empty(), "uids survive undo")


func _check_stairs() -> void:
	print("-- stairs")
	var m := _fresh()
	m.add_floor(1)
	m.add_floor(-1)
	var t := Vector3i(4, 0, 4)
	var partner := m.stairs_partner(t, {"dir": "up", "face": Kinds.DIRECTIONS["N"]})
	_check(partner["tile"] == Vector3i(4, 1, 4), "a flight that climbs meets one above")
	_check(
		partner["props"]["dir"] == "down" and partner["props"]["face"] == Kinds.DIRECTIONS["S"],
		"...that descends, facing back"
	)
	partner = m.stairs_partner(t, {"dir": "down", "face": Kinds.DIRECTIONS["E"]})
	_check(
		partner["tile"] == Vector3i(4, -1, 4) and partner["props"]["face"] == Kinds.DIRECTIONS["W"],
		"one that descends meets one below"
	)
	_check(
		(
			m
			. stairs_partner(Vector3i(4, 1, 4), {"dir": "up", "face": Kinds.DIRECTIONS["N"]})
			. is_empty()
		),
		"no storey above, no partner"
	)
	var box := [-1]
	_undoable(m, "place a flight with its partner", func(): box[0] = m.place_stairs(t, "up", "N"))
	var uid: int = box[0]
	var partner_uid: int = m.last_partner_uid
	_check(uid >= 0 and partner_uid >= 0, "both ends were placed")
	var up := m.placement(partner_uid)
	_check(
		up["tile"] == Vector3i(4, 1, 4) and up["props"]["dir"] == "down",
		"the other end is on the next storey"
	)
	_check(not m.plan.floor_tiles.has(t), "stairs are not floor")
	# Placing again replaces rather than piles up.
	m.place_stairs(t, "up", "E")
	var count := 0
	for p in m.plan.placements:
		if p["kind"] == &"stairs":
			count += 1
	_check(count == 2, "a flight placed again replaces the old one and its partner")
	_check(m.place_stairs(t, "sideways", "N") == -1, "a direction that is neither up nor down")
	_check(m.place_stairs(t, "up", "Q") == -1, "a face that is not N, E, S or W")
	m.place_stairs(Vector3i(6, 0, 6), "up", "N", false)
	_check(
		m.last_partner_uid == -1 and m.placements_at(Vector3i(6, 1, 6)).is_empty(),
		"no partner when not asked"
	)
	uid = m.placements_at(t)[0]["uid"]
	_undoable(m, "remove a flight with its partner", func(): m.remove_placement(uid, true))
	_check(
		m.placements_at(Vector3i(4, 1, 4)).is_empty() and m.plan.floor_tiles.has(t),
		"both ends are gone, floor left"
	)


func _check_entrance_and_exits() -> void:
	print("-- entrance and exits")
	var m := _fresh()
	var e := Vector3i(1, 0, 1)
	_undoable(m, "set the entrance", func(): m.set_entrance(e, "S", "W"))
	_check(m.plan.entrance == e and m.plan.has_entrance, "the entrance is there")
	_check(m.plan.tile_props[e]["facing"] == Kinds.DIRECTIONS["S"], "facing")
	_check(m.plan.tile_props[e]["exit_edge"] == Kinds.DIRECTIONS["W"], "exit edge")
	var f := Vector3i(8, 0, 8)
	_undoable(m, "move the entrance", func(): m.set_entrance(f, "N", "S"))
	_check(m.plan.entrance == f, "a second entrance moves the first")
	_undoable(m, "clear the entrance", func(): m.clear_entrance())
	var x := Vector3i(9, 0, 5)
	_undoable(m, "add an exit", func(): m.add_exit(x, "E"))
	m.add_exit(Vector3i(0, 0, 5), "W")
	_check(m.plan.exits.size() == 2, "two exits")
	_check(m.plan.tile_props[x]["exit_edge"] == Kinds.DIRECTIONS["E"], "an exit's edge")
	_undoable(m, "remove an exit", func(): m.remove_exit(x))
	_check(not m.remove_exit(Vector3i(3, 0, 3)), "removing what is not an exit")
	m.paint([Vector3i(3, 0, 3)], &"wall")
	m.set_entrance(Vector3i(3, 0, 3), "N")
	_check(
		m.plan.floor_tiles.has(Vector3i(3, 0, 3)) and not m.plan.wall_tiles.has(Vector3i(3, 0, 3)),
		"an entrance on a wall makes it floor"
	)


func _check_tile_props() -> void:
	print("-- tile properties")
	var m := _fresh()
	var t := Vector3i(3, 0, 3)
	_undoable(m, "set a note", func(): m.set_tile_prop(t, "note", "hello"))
	_undoable(m, "set tags", func(): m.set_tile_prop(t, "tags", ["a", "b"]))
	_undoable(m, "set an asset", func(): m.set_tile_prop(t, "asset", "res://x.glb"))
	_undoable(m, "set a facing by letter", func(): m.set_tile_prop(t, "facing", "W"))
	_undoable(m, "set an exit edge", func(): m.set_tile_prop(t, "exit_edge", Kinds.DIRECTIONS["S"]))
	_undoable(m, "set a custom property", func(): m.set_tile_prop(t, "custom.k", "v"))
	_undoable(m, "remove a note", func(): m.set_tile_prop(t, "note", ""))
	_check(not m.set_tile_prop(t, "bogus", "x"), "an unknown name is refused")
	_check(not m.set_tile_prop(t, "tags", "a,b"), "tags must be a list")
	_check(not m.set_tile_prop(t, "note", 'say "hi"'), "a quote cannot be written")
	for name in ["note", "tags", "asset", "facing", "exit_edge", "custom.k"]:
		m.set_tile_prop(t, name, "")
	_check(not m.plan.tile_props.has(t), "a tile with no property left has no entry")
	m.paint([t], &"ice")
	m.set_tile_prop(t, "note", "x")
	_check(m.tile_props(t) == {"note": "x"}, "the ice surface is not a designer's property")
	m.set_tile_prop(t, "note", "")
	_check(m.terrain_of(t) == &"ice", "...and stays when the notes go")


func _check_zones() -> void:
	print("-- zones")
	var m := _fresh()
	_undoable(m, "create a zone", func(): m.create_zone("hall", ["safe"]))
	_check(not m.create_zone("hall"), "a name is taken once")
	_check(not m.create_zone("bad name"), "a name with a space")
	_check(not m.create_zone(""), "an empty name")
	var tiles := Util.rect_tiles(Vector3i(1, 0, 1), Vector3i(3, 0, 2))
	_undoable(m, "paint a zone", func(): m.zone_paint("hall", tiles))
	_check(m.plan.zones["hall"]["tiles"].size() == 6, "six tiles")
	_check(m.zones_at(Vector3i(2, 0, 2)) == ["hall"], "zones_at")
	_undoable(m, "erase from a zone", func(): m.zone_erase("hall", [Vector3i(1, 0, 1)]))
	_undoable(m, "change a zone's tags", func(): m.set_zone_tags("hall", ["no_teleport"]))
	_undoable(m, "give a zone a note", func(): m.set_zone_prop("hall", "note", "n"))
	_undoable(m, "delete a zone", func(): m.delete_zone("hall"))
	_check(not m.delete_zone("hall"), "deleting twice is refused")
	_check(not m.zone_paint("nope", tiles) and m.last_error == "NO_SUCH_ZONE", "no such zone")
	# A zone with no tile is not written, and a zone round trips through the files.
	m.create_zone("empty")
	m.create_zone("z", ["t"])
	m.zone_paint("z", [Vector3i(0, 0, 0), Vector3i(5, 0, 5)])
	var back := _parse_texts(Writer.write_all(m.plan, m.floors))
	_check(back.zones.has("z") and not back.zones.has("empty"), "an empty zone is not saved")
	_check(back.zones["z"]["tiles"].size() == 2, "...and the others are")


func _check_floors() -> void:
	print("-- storeys")
	var m := _fresh()
	_undoable(m, "add a storey", func(): m.add_floor())
	_check(m.floors == [0, 1], "the next one up")
	_undoable(m, "add a storey below", func(): m.add_floor(-3))
	_check(m.floors == [-3, 0, 1], "kept in order")
	_check(not m.add_floor(0) and m.last_error == "FLOOR_EXISTS", "a storey is added once")
	m.paint_rect(Vector3i(0, 1, 0), Vector3i(3, 1, 3), &"floor")
	m.place(&"chest", Vector3i(1, 1, 1))
	m.create_zone("z")
	m.zone_paint("z", [Vector3i(1, 1, 1), Vector3i(1, 0, 1)])
	m.set_entrance(Vector3i(2, 1, 2), "N", "S")
	m.add_exit(Vector3i(3, 1, 3), "E")
	m.set_tile_prop(Vector3i(0, 1, 0), "note", "x")
	_undoable(m, "delete a storey", func(): m.delete_floor(1))
	_check(m.floors == [-3, 0], "the storey is gone")
	_check(
		(
			_count_y(m.plan.floor_tiles, 1) == 0
			and not m.plan.has_entrance
			and m.plan.exits.is_empty()
		),
		"with everything on it"
	)
	_check(m.plan.zones["z"]["tiles"].size() == 1, "...and its part of a zone")
	_check(not m.delete_floor(7), "no such storey")
	var solo := Model.new()
	solo.new_dungeon(&"s", TEMP)
	_check(not solo.delete_floor(0), "the last storey stays")


func _check_grouping_and_dirty() -> void:
	print("-- commands and the dirty flag")
	var m := _fresh()
	_check(not m.dirty and not m.can_undo() and not m.can_redo(), "a fresh model is clean")
	m.begin("stroke")
	m.paint([Vector3i(1, 0, 1)], &"wall")
	m.paint([Vector3i(2, 0, 1)], &"wall")
	m.paint([Vector3i(3, 0, 1)], &"wall")
	m.commit()
	_check(m._undo.size() == 1, "three paints in a stroke are one command")
	m.undo()
	_check(m.plan.wall_tiles.is_empty(), "one undo takes the whole stroke back")
	_check(not m.dirty, "undone to the start: clean again")
	m.redo()
	_check(m.dirty, "redone: dirty")
	_check(not m.can_redo(), "nothing left to redo")
	m.undo()
	m.paint([Vector3i(5, 0, 5)], &"wall")
	_check(not m.can_redo(), "a new command clears the redo branch")
	m.begin("empty")
	m.commit()
	_check(m._undo.size() == 1, "a command that changed nothing is not recorded")
	m.paint([Vector3i(5, 0, 5)], &"wall")
	_check(m._undo.size() == 1, "painting what is already there is not a command")
	var count := [0]
	m.changed.connect(func(): count[0] += 1)
	m.paint([Vector3i(6, 0, 5)], &"wall")
	m.undo()
	m.redo()
	_check(count[0] == 3, "changed is emitted by every command, undo and redo")
	# Save clears dirty; undoing past the save point makes it dirty again.
	var saved := Model.new()
	saved.new_dungeon(&"t_dirty", TEMP)
	saved.paint([Vector3i(1, 0, 1)], &"floor")
	_check(saved.dirty, "painting makes it dirty")
	saved.save()
	_check(not saved.dirty, "saving makes it clean")
	saved.paint([Vector3i(2, 0, 1)], &"floor")
	saved.undo()
	_check(not saved.dirty, "undoing back to the saved state is clean")
	saved.undo()
	_check(saved.dirty, "undoing past the saved state is dirty")
	saved.redo()
	_check(not saved.dirty, "redoing to it is clean")
	saved.undo()
	saved.paint([Vector3i(7, 0, 7)], &"floor")
	saved.redo()
	_check(saved.dirty, "a branch that can no longer reach the saved state stays dirty")


func _check_validation() -> void:
	print("-- validation of an edited plan")
	var m := Model.new()
	m.load_dungeon(LAKE)
	var base := m.validate()
	var base_errors := 0
	for i in base:
		if i["severity"] == "error":
			base_errors += 1
	_check(base_errors == 0, "the lake validates with no error")
	var waived := 0
	for i in base:
		if i.has("waived"):
			waived += 1
	_check(waived > 0, "...and its waived issues say so")
	# Break it: stairs need floor around them, a hazard does not belong in a safe zone.
	var inside := Vector3i(9, 0, 10)
	m.create_zone("calm", ["safe"])
	m.zone_paint("calm", [inside, Vector3i(10, 0, 10)])
	_check(m.plan.floor_tiles.has(inside), "(that tile is floor)")
	m.place(&"trap", inside, {"type": "poison"})
	var codes := {}
	for i in m.validate():
		if i["severity"] == "error":
			codes[i["code"]] = i
	_check(codes.has("SAFE_HAZARD"), "a trap in a safe zone is an error")
	_check(codes.has("SAFE_HAZARD") and codes["SAFE_HAZARD"]["tile"] == inside, "...on its tile")
	m.undo()
	m.undo()
	m.undo()
	var again := 0
	for i in m.validate():
		if i["severity"] == "error":
			again += 1
	_check(again == 0, "undo clears it")
	m.clear_entrance()
	var found := false
	for i in m.validate():
		found = found or i["code"] == "NO_ENTRANCE"
	_check(found, "no entrance is reported")
	# A new dungeon with an island nobody reaches.
	var n := Model.new()
	n.new_dungeon(&"t", TEMP)
	n.paint_rect(Vector3i(0, 0, 0), Vector3i(3, 0, 3), &"floor")
	n.paint_rect(Vector3i(8, 0, 8), Vector3i(9, 0, 9), &"floor")
	n.set_entrance(Vector3i(0, 0, 0), "S", "N")
	var unreachable: Variant = null
	for i in n.validate():
		if i["code"] == "UNREACHABLE":
			unreachable = i
	_check(unreachable != null and unreachable["severity"] == "error", "an island is unreachable")
	n.create_zone("island", ["unreachable_ok"])
	n.zone_paint("island", Util.rect_tiles(Vector3i(8, 0, 8), Vector3i(9, 0, 9)))
	var still := false
	for i in n.validate():
		still = still or i["code"] == "UNREACHABLE"
	_check(not still, "...unless a zone tag says it may be")
	# What the parser could not read is shown until the next save.
	var bad := Model.new()
	bad.load_dungeon(&"no_such_dungeon_here")
	var has_issue := false
	for i in bad.validate():
		has_issue = has_issue or i["code"] == "NO_DIRECTORY"
	_check(has_issue, "a missing dungeon says so")
	_check(bad.floors == [0] and bad.extent().x >= 1, "...and loads as an empty storey")


func _check_save_and_load() -> void:
	print("-- save and load, in a temporary directory")
	var m := _inline_model()
	m.slug = &"saved"
	m.plan.slug = &"saved"
	m.root = TEMP
	var before := Util.canonical(m.plan)
	_check(m.save() == OK, "save")
	_check(m.last_written.size() == 2, "one file per storey: %s" % [m.last_written])
	_check(not m.dirty, "clean after saving")
	_check(m.save() == OK and m.last_written.is_empty(), "saving again touches nothing")
	_check(FileAccess.file_exists(TEMP + "saved/floor_0.map"), "floor_0.map exists")
	var n := Model.new()
	n.load_dungeon(&"saved", TEMP)
	_check(n.floors == [0, 1], "the storeys come back")
	_check(Util.canonical(n.plan) == before, "load(save(plan)) is the same plan")
	_check(n.load_issues.is_empty(), "with no issue")
	_check(n.grid_size == m.extent(), "and the same grid")
	_check(n.save() == OK and n.last_written.is_empty(), "a loaded dungeon saves byte for byte")
	# Edit, save, delete a storey, save: the file goes.
	n.paint([Vector3i(0, 0, 12)], &"wall")
	n.save()
	_check(n.last_written == ["floor_0.map"], "only the edited storey is written")
	n.delete_floor(1)
	n.save()
	_check(
		not FileAccess.file_exists(TEMP + "saved/floor_1.map"), "a removed storey's file is deleted"
	)
	_check("-floor_1.map" in n.last_written, "...and reported")
	var o := Model.new()
	o.load_dungeon(&"saved", TEMP)
	_check(o.floors == [0], "reloaded: one storey")
	# A dungeon with nothing but a rules.cfg or a partial folder loads.
	DirAccess.make_dir_recursive_absolute(TEMP + "partial")
	var f := FileAccess.open(TEMP + "partial/floor_3.map", FileAccess.WRITE)
	f.store_string("[floor]\ny = 3\n[grid]\n..#\n[tiles]\nZZ99 bogus_kind\n")
	f.close()
	var p := Model.new()
	p.load_dungeon(&"partial", TEMP)
	_check(p.floors == [3], "a partial dungeon loads its one storey")
	_check(not p.load_issues.is_empty(), "...with the issue the parser had")
	_check(p.validate().size() > 0, "...which validation shows")
	p.save()
	_check(p.load_issues.is_empty(), "...until a save writes what was readable")
	# A new dungeon saves its first file.
	var q := Model.new()
	q.new_dungeon(&"brand_new", TEMP)
	q.paint([Vector3i(1, 0, 1)], &"floor")
	_check(
		q.save() == OK and FileAccess.file_exists(TEMP + "brand_new/floor_0.map"),
		"a new dungeon saves"
	)
	_check(
		not FileAccess.file_exists(TEMP + "brand_new/rules.cfg"), "...with no rules.cfg of its own"
	)
	_check(
		Util.valid_slug("a_b2") and not Util.valid_slug("A b") and not Util.valid_slug(""), "slugs"
	)
	# Never into data/ by accident: the default root is only used when asked for.
	_check(m.root == TEMP, "the check saves under the temporary root")


func _check_emerge() -> void:
	print("-- the emerge tile")
	var real := FileAccess.get_file_as_string("res://data/dungeons/%s/rules.cfg" % LAKE)
	DirAccess.make_dir_recursive_absolute(TEMP + "lake")
	var f := FileAccess.open(TEMP + "lake/rules.cfg", FileAccess.WRITE)
	f.store_string(real)
	f.close()
	var m := Model.new()
	m.load_dungeon(LAKE)
	m.root = TEMP
	_check(m.emerge_tile() == Vector3i(5, 0, 24), "the lake's emerge tile is F25@0")
	m.slug = &"lake"
	_check(m.save() == OK and not m.last_written.has("rules.cfg"), "unedited: rules.cfg untouched")
	_check(FileAccess.get_file_as_string(TEMP + "lake/rules.cfg") == real, "...byte for byte")
	_undoable(m, "set the emerge tile", func(): m.set_emerge(Vector3i(7, 0, 8)))
	_check(m.emerge_tile() == Vector3i(7, 0, 8), "the plan knows it")
	_check(m.save() == OK and m.last_written.has("rules.cfg"), "a save writes rules.cfg")
	var patched := FileAccess.get_file_as_string(TEMP + "lake/rules.cfg")
	_check(
		patched == real.replace('emerge="F25@0"', 'emerge="H9@0"'), "...changing only that one line"
	)
	_check(m.save() == OK and m.last_written.is_empty(), "and only once")


func _clean_temp() -> void:
	_remove_dir(TEMP)


func _remove_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_remove_dir(path.path_join(sub))
	for f in dir.get_files():
		dir.remove(f)
	DirAccess.remove_absolute(path)
