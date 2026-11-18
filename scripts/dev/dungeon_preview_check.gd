## Headless check of the dungeon preview tools: the ASCII dump, the PNG renderer, the statistics,
## and the walk that cross-checks the validator against the engine — on small inline plans, and
## on the committed frozen lake. The walk is also shown to go red: a plan whose staircase the
## engine does not have disagrees with the validator, which still believes in it.
##
## Run with: Godot --headless --path . res://scenes/dev/dungeon_preview_check.tscn
## As a start scene rather than --script; see geometry_check.gd.
extends Node

const Parser := preload("res://scripts/dungeon/dungeon_map_parser.gd")
const Plan := preload("res://scripts/dungeon/dungeon_plan.gd")
const Loader := preload("res://scripts/dungeon/dungeon_loader.gd")
const Validator := preload("res://scripts/dungeon/dungeon_validator.gd")
const View := preload("res://scripts/dungeon/dungeon_view.gd")
const Dump := preload("res://scripts/dungeon/dungeon_dump.gd")
const Png := preload("res://scripts/dungeon/dungeon_png.gd")
const Stats := preload("res://scripts/dungeon/dungeon_stats.gd")
const Walk := preload("res://scripts/dungeon/dungeon_walk.gd")
const Stairs := preload("res://scripts/exploration/mechanisms/stairs.gd")
const Guardrail := preload("res://scripts/exploration/mechanisms/guardrail.gd")
const ScenarioCatalog := preload("res://scripts/dev/scenario_catalog.gd")

## Two storeys: a flight of stairs, a cracked wall and a gate on the way, an exit upstairs.
const GROUND := """[floor]
y = 0
[grid]
#######
#E..>_#
#.k.g.#
#######
[legend]
> = stairs dir=up face=E
k = cracked_wall axis=ew
g = gate type=automated edge=E
[tiles]
B2 facing=N exit_edge=W
"""
const UPPER := """[floor]
y = 1
[grid]
#######
#####.X
#######
[tiles]
G2 exit_edge=E
"""

## A single storey with one of most things, to look at in the dump and the picture.
const SAMPLE := """[floor]
y = 0
[grid]
#########
#E.cT.iX#
#.^.=~.b#
#r.%s.#:#
#########
[legend]
c = chest trapped=true
T = trap type=teleport
^ = stairs dir=up face=N
= = guardrail edge=E
b = bridge over=void
r = crumbly
% = litter
s = rival_spawn
[tiles]
B2 facing=E exit_edge=W
H2 exit_edge=E
[zones]
hall tags=safe rect=C2:D3
"""

const EXPECTED_DUMP := """sample: floor 0

== floor 0 ==  A1:I5
  ABCDEFGHI
1 #########
2 #E.CT.iX#
3 #.^.H~.b#
4 #r.%s.#:#
5 #########
zones:
  ABCDEFGHI
2   11
3   11
  1 = hall  [safe]

legend:
  E  entrance
  X  exit
  ^  stairs up, face N
  T  teleport trap
  C  trapped chest
  H  guardrail on an east or west edge
  b  bridge over a drop
  r  crumbly ground
  %  litter
  s  rival spawn point
  .  floor
  i  ice
  ~  water
  #  wall
  :  hole
"""

## The colours the pictures must have, written out here rather than read from the renderer: a
## check that compares the renderer with its own constants cannot notice a change to them.
const C_WALL := Color8(0, 0, 0)
const C_WATER := Color8(46, 68, 102)
const C_ICE := Color8(88, 160, 160)
const C_GROUND := Color8(64, 64, 64)
const C_HOLE := Color8(20, 0, 30)
const C_EMPTY := Color8(255, 255, 255)
const C_RED := Color8(230, 30, 30)
const C_AMBER := Color8(255, 150, 0)

## How many checks a complete run makes. A script error in the middle of a section ends it
## quietly, and the checks after the error would never be counted as failures.
const CHECKS := 61

var _fails: Array[String] = []
var _ran := 0


func _check(cond: bool, label: String) -> void:
	_ran += 1
	if cond:
		print("  OK   %s" % label)
	else:
		print("  FAIL %s" % label)
		_fails.append(label)


func _ready() -> void:
	await get_tree().process_frame
	_check_cells()
	_check_dump()
	_check_png()
	_check_stats()
	await _check_walk_small()
	await _check_walk_rigged()
	await _check_walk_lake()
	if _ran != CHECKS:
		_fails.append("%d checks ran, %d expected: a section stopped early" % [_ran, CHECKS])
		print("  FAIL %s" % _fails[-1])
	if _fails.is_empty():
		print("All checks pass.")
		get_tree().quit(0)
	else:
		print("%d check(s) failed." % _fails.size())
		get_tree().quit(1)


func _plan_of(texts: Array, slug: StringName = &"sample") -> Plan:
	var plan := Plan.new()
	plan.slug = slug
	for i in texts.size():
		Parser.new().read_floor(plan, texts[i], "fixture%d.map" % i)
	return plan


# --------------------------------------------------------------------------
# Cells
# --------------------------------------------------------------------------


func _check_cells() -> void:
	_check(View.column_name(0) == "A" and View.column_name(25) == "Z", "columns A..Z")
	_check(View.column_name(26) == "AA" and View.column_name(30) == "AE", "...then AA..AE")
	_check(View.cell_name(27, 23) == "AB24", "AB24 is tile (27, 23)")
	_check(View.parse_rect("B2:D3") == Rect2i(1, 1, 3, 2), "a rectangle, as cell names")
	_check(View.parse_rect("B2:D3") == View.parse_rect("D3:B2"), "...whichever corner comes first")
	_check(View.parse_rect("nonsense") == null, "...and nothing for nonsense")


# --------------------------------------------------------------------------
# The ASCII dump
# --------------------------------------------------------------------------


func _check_dump() -> void:
	var plan := _plan_of([SAMPLE])
	if Dump.render(plan) != EXPECTED_DUMP:
		print("--- the dump came out as:\n" + Dump.render(plan) + "---")
	_check(
		Dump.render(plan) == EXPECTED_DUMP, "the dump of a small plan is exactly what it should be"
	)
	var text := Dump.render(plan, {"list": true})
	_check(text.contains("D2 ") and text.contains(" chest "), "--list names the chest's cell")
	_check(
		text.contains("trapped=true") and text.contains("type=teleport"), "...with its properties"
	)
	_check(
		Dump.render(plan, {"rect": Rect2i(1, 1, 3, 2)}).contains("== floor 0 ==  B2:D3"),
		"--rect cuts the view"
	)
	_check(Dump.render(plan, {"zone": "hall"}).contains("hall"), "--zone names its zone")
	_check(Dump.problem(plan, {"zone": "nope"}) != "", "an unknown zone is a problem")
	_check(Dump.problem(plan, {"floor": 7}) != "", "so is an unknown floor")
	var issue := {
		"severity": "error",
		"code": "UNREACHABLE",
		"tile": Vector3i(2, 0, 1),
		"source": "",
		"args": [1, "2,0,1"]
	}
	var marked := Dump.render(plan, {"issues": [issue]})
	_check(marked.contains("2 #E!CT.iX#"), "--issues puts a ! on the tile")
	_check(marked.contains("error   C2"), "...and lists the issue by cell")
	# Placement glyphs stay distinct from one another.
	var seen := {}
	var clash := false
	for entry in Dump.LEGEND:
		if seen.has(entry[0]):
			clash = true
		seen[entry[0]] = true
	_check(not clash, "no two legend entries share a character")
	var traps := {
		Dump.placement_glyph({"kind": &"trap", "props": {"type": "disarray"}}): true,
		Dump.placement_glyph({"kind": &"trap", "props": {"type": "teleport"}}): true,
		Dump.placement_glyph({"kind": &"trap", "props": {"type": "poison"}}): true,
	}
	_check(traps.size() == 3, "the three trap kinds look different")
	var stairs := {}
	for dir in ["up", "down"]:
		for face in [Vector3i(0, 0, -1), Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(-1, 0, 0)]:
			stairs[Dump.placement_glyph({"kind": &"stairs", "props": {"dir": dir, "face": face}})] = true
	_check(stairs.size() == 8, "stairs have eight glyphs: up and down, four faces")


# --------------------------------------------------------------------------
# The picture
# --------------------------------------------------------------------------


func _pixel(img: Image, extent: Rect2i, s: int, x: int, z: int, dx: int, dy: int) -> Color:
	var o := Png.tile_origin(extent, s, x, z)
	return img.get_pixel(o.x + dx, o.y + dy)


func _same(a: Color, b: Color) -> bool:
	return a.is_equal_approx(b)


func _check_png() -> void:
	var text := "[floor]\ny = 0\n[grid]\n#.i~:_#\n[zones]\nhall tags=no_teleport rect=B1:B1\n"
	var plan := _plan_of([text], &"tiny")
	var s := 12
	var extent := View.bounds(plan)
	var img := Png.render_floor(plan, 0, {"scale": s})
	var corner := s - 3  # clear of the centre, where an icon would go
	_check(_same(_pixel(img, extent, s, 0, 0, corner, corner), C_WALL), "a wall is black")
	_check(_same(_pixel(img, extent, s, 2, 0, corner, corner), C_ICE), "ice is teal")
	_check(_same(_pixel(img, extent, s, 3, 0, corner, corner), C_WATER), "water is dark blue")
	_check(_same(_pixel(img, extent, s, 4, 0, corner, s / 2), C_HOLE), "a hole is dark")
	_check(_same(_pixel(img, extent, s, 5, 0, corner, corner), C_EMPTY), "nothing is white")
	var ground := _pixel(img, extent, s, 1, 0, corner, corner)
	_check(not _same(ground, C_GROUND), "a zone tints the ground under it...")
	_check(ground.r > C_GROUND.r and ground.g < ground.r, "...towards magenta, for no_teleport")
	var again := Png.render_floor(plan, 0, {"scale": s})
	_check(
		img.save_png_to_buffer() == again.save_png_to_buffer(),
		"two renders are byte for byte the same"
	)
	var other := Png.render_floor(plan, 0, {"scale": 13})
	_check(other.get_width() != img.get_width(), "--scale changes the size")
	# An issue marker stands where the issue is, and nowhere else.
	var at := Vector3i(2, 0, 0)
	var error := {"severity": "error", "code": "X", "tile": at, "source": "", "args": []}
	var waived := {
		"severity": "warning", "code": "X", "tile": at, "source": "", "args": [], "waived": "later"
	}
	var plain := Png.render_floor(plan, 0, {"scale": s})
	var flagged := Png.render_floor(plan, 0, {"scale": s, "issues": [error]})
	var amber := Png.render_floor(plan, 0, {"scale": s, "issues": [waived]})
	_check(
		_same(_pixel(flagged, extent, s, 2, 0, s / 4 - 3, s / 4), C_RED),
		"an error is a red badge on its tile"
	)
	_check(
		not _same(_pixel(plain, extent, s, 2, 0, s / 4 - 3, s / 4), C_RED),
		"...absent without --issues"
	)
	_check(
		_same(
			_pixel(flagged, extent, s, 1, 0, s / 4 - 3, s / 4),
			_pixel(plain, extent, s, 1, 0, s / 4 - 3, s / 4)
		),
		"...and absent from the tiles beside it"
	)
	_check(
		_same(_pixel(amber, extent, s, 2, 0, s / 4 - 3, s / 4), C_AMBER), "a waived issue is orange"
	)
	# Placements leave their mark: the sample's chest is not the colour of bare ground.
	var sample := _plan_of([SAMPLE])
	var big := Png.render_floor(sample, 0, {"scale": 24})
	var box := View.bounds(sample)
	var middle := _pixel(big, box, 24, 3, 1, 12, 12)
	_check(not _same(middle, C_GROUND) and middle.r > middle.b, "a chest is gold on its tile")
	var contact := Png.contact_sheet({0: big, 1: big})
	_check(contact.get_width() > 2 * big.get_width(), "the contact sheet holds both storeys")


# --------------------------------------------------------------------------
# Statistics
# --------------------------------------------------------------------------


func _check_stats() -> void:
	var plan := _plan_of([SAMPLE])
	var validator := Validator.new()
	var issues := validator.validate(plan)
	var stats := Stats.compute(plan, issues, validator.reachable_from_entrance(plan))
	var total: Dictionary = stats["total"]
	_check(total["floor"] == 17, "stats: floor tiles (%d)" % total["floor"])
	_check(
		total["ice"] == 1 and total["water"] == 1 and total["hole"] == 1, "stats: ice, water, hole"
	)
	_check(total["pit"] == 1, "stats: one pit under the plank")
	_check(
		total["placements"].get("chest", 0) == 1 and total["placements"].get("stairs", 0) == 1,
		"stats: placements per kind"
	)
	_check(total["rival_spawns"] == 1 and total["special_spawns"] == 0, "stats: spawn points")
	_check(total["exits"] == 1 and total["entrance"] == 1, "stats: an entrance and an exit")
	_check(total["zone_tiles"] == 4, "stats: the zone's tiles")
	_check(stats["entrance"] == "B2@0" and stats["exits"] == ["H2@0"], "stats: where they are")
	_check(
		total["reachable"] > 0 and total["reachable"] <= total["floor"], "stats: reachable tiles"
	)
	_check(total["bounds"] == "A1:I5", "stats: the bounding box")
	_check(
		stats["rivals_at_entry"] == 0 and stats["spawn_points_enough"], "stats: no rival required"
	)
	var json: Variant = JSON.parse_string(Stats.to_json(stats))
	_check(json is Dictionary and json["slug"] == "sample", "stats: the JSON reads back")
	_check(Stats.format_text(stats).contains("floor tiles"), "stats: the table has its rows")
	var wanted := _plan_of([SAMPLE])
	wanted.rules["spawn_at_entry"] = {"rivals": 5}
	var short := Stats.compute(wanted, [], {})
	_check(
		short["rivals_at_entry"] == 5 and not short["spawn_points_enough"],
		"stats: too few spawn points are seen"
	)


# --------------------------------------------------------------------------
# The walk
# --------------------------------------------------------------------------


func _build(plan: Plan) -> DungeonManager:
	var dm := DungeonManager.new()
	add_child(dm)
	Loader.build_plan(plan, dm)
	return dm


## Frees a manager and waits until it is gone: mechanisms register with the FIRST node in the
## `dungeon` group, so a manager left standing would take the next one's mechanisms.
func _discard(dm: DungeonManager) -> void:
	remove_child(dm)
	dm.queue_free()
	await get_tree().process_frame


func _check_walk_small() -> void:
	var plan := _plan_of([GROUND, UPPER], &"two_floors")
	var dm := _build(plan)
	var report := Walk.walk(plan, dm)
	_check(
		report["disagreements"] == 0, "walk: the engine and the validator agree on two small floors"
	)
	_check(
		report["reached"].has(Vector3i(6, 1, 1)),
		"walk: the engine climbs the stairs to the exit upstairs"
	)
	_check(
		report["reached"].has(Vector3i(5, 0, 2)),
		"walk: ...and crosses the cracked wall and the gate"
	)
	var flags := {}
	for item in report["items"]:
		flags[item["kind"]] = item["engine"] and item["validator"]
	_check(
		flags.get("exit", false) and flags.get("stairs", false),
		"walk: the exit and the stairs are reached by both"
	)
	_check(
		Walk.format_report(plan, report).contains("OK: the engine and the validator agree."),
		"walk: the report says so"
	)
	await _discard(dm)
	# Water nobody walks into is no way anywhere, and nobody objects.
	var wet := _plan_of(["[floor]\ny = 0\n[grid]\n#####\n#E.~#\n#####\n"], &"wet")
	var wet_dm := _build(wet)
	var wet_report := Walk.walk(wet, wet_dm)
	_check(wet_report["disagreements"] == 0, "walk: a pool beside the path is no disagreement")
	_check(wet_report["skipped"].is_empty(), "walk: ...and a step into it is no move, so none is skipped")
	await _discard(wet_dm)


func _check_walk_rigged() -> void:
	var plan := _plan_of([GROUND, UPPER], &"two_floors")
	var dm := _build(plan)
	var stairs: Array = []
	for child in dm.get_children():
		if child.get_script() == Stairs:
			stairs.append(child)
	_check(stairs.size() == 1, "rig: the staircase is there to be taken out")
	for st in stairs:
		dm.remove_child(st)
		st.free()
	var report := Walk.walk(plan, dm)
	_check(report["disagreements"] > 0, "rig: without the engine's staircase, the walk disagrees")
	_check(
		report["validator_only"].has(Vector3i(6, 1, 1)),
		"rig: ...it is the exit upstairs the engine cannot reach"
	)
	_check(Walk.format_report(plan, report).contains("DISAGREE"), "rig: ...and the report says so")
	await _discard(dm)
	# The other way round: a rail the plan does not know about shuts a corridor in the engine only.
	var narrow := _plan_of(["[floor]\ny = 0\n[grid]\n#####\n#E..#\n#####\n"], &"corridor")
	var corridor := _build(narrow)
	ScenarioCatalog.place(corridor, Guardrail, Vector3i(2, 0, 1), {"edge_dir": Vector3i(1, 0, 0)})
	var shut := Walk.walk(narrow, corridor)
	_check(
		shut["disagreements"] > 0 and shut["validator_only"].has(Vector3i(3, 0, 1)),
		"rig: a rail only the engine has is a disagreement too"
	)
	await _discard(corridor)


func _check_walk_lake() -> void:
	var dm := DungeonManager.new()
	add_child(dm)
	var built := Loader.build(&"norgzevod_frozen_lake", dm)
	var report := Walk.walk(built["plan"], dm)
	_check(
		report["disagreements"] == 0,
		"walk: the frozen lake — engine and validator agree on every tile"
	)
	var exits := 0
	for item in report["items"]:
		if item["kind"] == "exit" and item["engine"]:
			exits += 1
	_check(
		exits == built["plan"].exits.size(),
		"walk: the engine reaches all %d exits of the lake" % exits
	)
	await _discard(dm)
