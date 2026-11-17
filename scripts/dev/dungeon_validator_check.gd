## Headless check of the dungeon map parser and validator, on small maps written inline: a sound
## one that reports nothing, then one broken map per rule, so that a rule that stops firing is
## noticed.
##
## Run with: Godot --headless --path . res://scenes/dev/dungeon_validator_check.tscn
## As a start scene rather than --script; see geometry_check.gd.
extends Node

const Parser := preload("res://scripts/dungeon/dungeon_map_parser.gd")
const Validator := preload("res://scripts/dungeon/dungeon_validator.gd")
const Plan := preload("res://scripts/dungeon/dungeon_plan.gd")

var _fails: Array[String] = []


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  OK   %s" % label)
	else:
		print("  FAIL %s" % label)
		_fails.append(label)


func _ready() -> void:
	await get_tree().process_frame
	_check_sound()
	_check_parser()
	_check_reachability()
	_check_holes_and_bridges()
	_check_stairs()
	_check_teleports_and_zones()
	_check_safe_areas()
	_check_assets_and_props()
	_check_terrain_and_cells()
	_check_water()
	_check_exits()
	_check_waivers_and_rules()
	_check_committed_dungeons()
	if _fails.is_empty():
		print("All checks pass.")
		get_tree().quit(0)
	else:
		print("%d check(s) failed." % _fails.size())
		get_tree().quit(1)


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------


## One storey's text from a header and its parts.
func _floor(y: int, grid: Array, extra: String = "") -> String:
	return "[floor]\ny = %d\n[grid]\n%s\n%s" % [y, "\n".join(grid), extra]


func _plan_of(floors: Array, rules: Dictionary = {}) -> Plan:
	var plan := Plan.new()
	plan.rules = rules
	for i in floors.size():
		Parser.new().read_floor(plan, floors[i], "fixture_%d.map" % i)
	return plan


func _issues(floors: Array, rules: Dictionary = {}) -> Array:
	return Validator.new().validate(_plan_of(floors, rules))


func _codes(floors: Array, rules: Dictionary = {}) -> Array:
	var out: Array = []
	for i in _issues(floors, rules):
		out.append(i["code"])
	return out


func _has(floors: Array, code: String, rules: Dictionary = {}) -> bool:
	return _codes(floors, rules).has(code)


# --------------------------------------------------------------------------
# Checks
# --------------------------------------------------------------------------


func _check_sound() -> void:
	var sound := [
		_floor(
			0,
			["#######", "#E...X#", "#######"],
			"[tiles]\nB2 facing=E exit_edge=W\nF2 exit_edge=E\n"
		)
	]
	_check(_issues(sound).is_empty(), "a sound map reports nothing")
	_check(
		Validator.error_count([{"severity": "error"}, {"severity": "warning"}]) == 1,
		"only errors count towards a failure"
	)


func _check_parser() -> void:
	var plan := _plan_of(
		[
			_floor(
				0,
				["#######", "#E.T.c#", "#######"],
				(
					"[legend]\nT = trap type=poison poison_turns=4\nc = chest loot=rune_stone,spade\n"
					+ '[tiles]\n3,1 note="a b c" tags=x,y\n5,1 revealed=true\n'
					+ "[zones]\nhall tags=safe,no_teleport rect=1,1:2,1\n"
				)
			)
		]
	)
	_check(plan.issues.is_empty(), "a file with every section reads clean")
	_check(plan.entrance == Vector3i(1, 0, 1) and plan.has_entrance, "E is the entrance")
	_check(plan.is_floor(Vector3i(3, 0, 1)), "a legend kind that is floor makes the tile floor")
	var trap: Dictionary = plan.placements_at(Vector3i(3, 0, 1))[0]
	_check(trap["kind"] == &"trap" and trap["props"]["poison_turns"] == 4, "typed integer")
	_check(trap["props"]["type"] == "poison", "typed enum")
	var chest: Dictionary = plan.placements_at(Vector3i(5, 0, 1))[0]
	_check(chest["props"]["loot"] == ["rune_stone", "spade"], "list value")
	var tp: Dictionary = plan.tile_props[Vector3i(3, 0, 1)]
	_check(tp["note"] == "a b c", "a quoted value keeps its spaces")
	_check(tp["tags"] == ["x", "y"], "tags are a list")
	_check(plan.has_tag(Vector3i(1, 0, 1), "no_teleport"), "a zone rect tags its tiles")
	_check(plan.has_tag(Vector3i(2, 0, 1), "safe"), "...both ends of it")
	_check(not plan.has_tag(Vector3i(3, 0, 1), "safe"), "...and nothing beyond")
	for text in [
		_floor(0, ["#E#"], "[legend]\nT = nonsense\n"),
		_floor(0, ["#Z#"]),
		"[grid]\n#E#\n",
		_floor(0, ["#E#"], "[tiles]\nnot a tile\n"),
		_floor(0, ["#E#", "#E#"]),
		_floor(0, ["#ET"], "[legend]\nT = trap type=bogus\n"),
	]:
		var bad := _plan_of([text])
		_check(not bad.issues.is_empty(), "a bad file is reported: %s" % text.replace("\n", "|"))


func _check_reachability() -> void:
	var cut := [_floor(0, ["#########", "#E..#..X#", "#########"])]
	_check(_has(cut, "UNREACHABLE"), "a pocket behind a wall is unreachable")
	_check(_has(cut, "EXIT_UNREACHABLE"), "...and an exit in it is said to be")
	var ok := [
		_floor(
			0,
			["#########", "#E..#..X#", "#########"],
			"[tiles]\n5,1 tags=unreachable_ok\n6,1 tags=unreachable_ok\n[zones]\nback tags=unreachable_ok rect=5,1:7,1\n"
		)
	]
	_check(not _has(ok, "UNREACHABLE"), "...unless the notes say it is meant")
	var rail := [
		_floor(
			0,
			["#######", "#E.|..#", "#######"],
			"[legend]\n| = guardrail edge=E\n"
		)
	]
	_check(_has(rail, "UNREACHABLE"), "a guardrail bars the step across its edge")
	var door := [
		_floor(0, ["#######", "#E.|..#", "#######"], "[legend]\n| = gate type=automated edge=E\n")
	]
	_check(not _has(door, "UNREACHABLE"), "a gate does not make the far side unreachable")
	var cracked := [_floor(0, ["#######", "#E.#..#", "#######"], "[tiles]\n3,1 cracked_wall\n")]
	_check(not _has(cracked, "UNREACHABLE"), "a cracked wall joins both sides")
	var lone := [_floor(0, ["#####", "#...#", "#####"])]
	_check(_has(lone, "NO_ENTRANCE"), "no entrance is an error")


func _check_holes_and_bridges() -> void:
	var pit := [_floor(0, ["#####", "#E:.#", "#####"])]
	_check(_has(pit, "BOTTOMLESS_HOLE"), "a hole with nothing below")
	var caught := [_floor(-1, ["#####", "#...#", "#####"]), _floor(0, ["#####", "#E:.#", "#####"])]
	_check(not _has(caught, "BOTTOMLESS_HOLE"), "...and one with a floor below is not")
	var legend := "[legend]\n= = bridge\n"
	# Floor y = 0 is the ravine bottom, y = 1 holds the bridge and its two ends.
	var good := [
		_floor(0, ["#######", "#.....#", "#######"], "[tiles]\n1,1 note=\"way up\"\n"),
		_floor(1, ["#######", "#E===.#", "#######"], legend),
	]
	_check(not _has(good, "BRIDGE_NO_GAP"), "a bridge over a ravine has its gap")
	var nowhere := [_floor(1, ["#######", "#E===.#", "#######"], legend)]
	_check(_has(nowhere, "BRIDGE_NO_GAP"), "a bridge over nothing")
	# The ravine floor is walled off from the entrance: a fall leaves no way back.
	_check(_has(good, "BRIDGE_NO_WAY_BACK"), "a fall that cannot climb back")


func _check_stairs() -> void:
	var legend := "[legend]\n^ = stairs dir=up face=E\n"
	var sound := [
		_floor(0, ["#######", "#E.^###", "#######"], legend),
		_floor(1, ["#######", "#.....#", "#######"]),
	]
	# The stairs on (3, 0, 1) face east: from (2, 0, 1) they carry to (4, 1, 1). Tile (3, 1, 1)
	# is the headroom and has to stay empty, so the upper storey needs a gap there.
	_check(_has(sound, "STAIRS_ABOVE"), "floor directly above the stairs is reported")
	var open_above := [
		_floor(0, ["#######", "#E.^###", "#######"], legend),
		_floor(1, ["#######", "#   ..#", "#######"]),
	]
	var faults := _codes(open_above)
	faults.erase("EXIT_NO_EDGE")
	faults.erase("ENTRANCE_NO_FACING")
	_check(faults.is_empty(), "stairs with headroom and a landing report nothing")
	var no_landing := [
		_floor(0, ["#######", "#E.^###", "#######"], legend),
		_floor(1, ["#######", "#    .#", "#######"]),
	]
	_check(_has(no_landing, "STAIRS_DESTINATION"), "stairs into nothing")
	var no_approach := [
		_floor(0, ["#######", "#E#^###", "#######"], legend),
		_floor(1, ["#######", "#   ..#", "#######"]),
	]
	_check(_has(no_approach, "STAIRS_APPROACH"), "no floor in front of the stairs")
	var faceless := [_floor(0, ["#####", "#E^.#", "#####"], "[legend]\n^ = stairs dir=up\n")]
	_check(_has(faceless, "STAIRS_FACE"), "stairs need a direction")
	# The upper storey is only reachable through the stairs: the link has to count.
	var far := [
		_floor(0, ["#######", "#E.^###", "#######"], legend),
		_floor(1, ["#######", "#   ..#", "#######"]),
	]
	_check(not _has(far, "UNREACHABLE"), "a storey reached by stairs is reachable")


func _check_teleports_and_zones() -> void:
	var legend := "[legend]\n| = gate type=teleport edge=E arrival=5,1\n"
	var grid := ["#######", "#E|##.#", "#######"]
	var plain := [_floor(0, grid, legend)]
	_check(not _has(plain, "UNREACHABLE"), "a teleport gate reaches its arrival tile")
	var restricted := [_floor(0, grid, legend + "[zones]\nsealed tags=no_teleport rect=5,1:5,1\n")]
	_check(_has(restricted, "TELEPORT_INTO_RESTRICTED"), "a teleport into a no_teleport zone")
	var nowhere := [_floor(0, grid, "[legend]\n| = gate type=teleport edge=E arrival=4,1\n")]
	_check(_has(nowhere, "GATE_ARRIVAL_NOT_FLOOR"), "a teleport onto a wall")
	var lost := [_floor(0, grid, "[legend]\n| = gate type=teleport edge=E\n")]
	_check(_has(lost, "GATE_NO_ARRIVAL"), "a teleport with no arrival")


func _check_safe_areas() -> void:
	var legend := "[legend]\nT = trap type=poison\nc = chest\n"
	var zone := "[zones]\nsafe tags=safe rect=1,1:3,1\n"
	var trap := [_floor(0, ["#####", "#ET.#", "#####"], legend + zone)]
	_check(_has(trap, "SAFE_HAZARD"), "a trap in a safe area")
	var chest := [_floor(0, ["#####", "#Ec.#", "#####"], legend + zone)]
	_check(not _has(chest, "SAFE_HAZARD"), "a plain chest is loot, not a hazard")
	var trapped := [_floor(0, ["#####", "#E.c#", "#####"], legend + "[tiles]\n3,1 chest trapped=true\n" + zone)]
	_check(_has(trapped, "SAFE_HAZARD"), "a trapped chest is a hazard")
	var ledge := [
		_floor(-1, ["#####", "#...#", "#####"]),
		_floor(0, ["#####", "#E.:#", "#####"], "[zones]\nsafe tags=safe rect=1,1:2,1\n"),
	]
	_check(_has(ledge, "SAFE_LEDGE"), "an unrailed ledge on a safe tile")
	var railed := [
		_floor(-1, ["#####", "#...#", "#####"]),
		_floor(
			0,
			["#####", "#E|:#", "#####"],
			"[legend]\n| = guardrail edge=E\n[zones]\nsafe tags=safe rect=1,1:2,1\n"
		),
	]
	_check(not _has(railed, "SAFE_LEDGE"), "...railed, it is not")


func _check_assets_and_props() -> void:
	var missing := [
		_floor(
			0,
			["#####", "#E.c#", "#####"],
			"[legend]\nc = chest asset=res://assets/nope.glb\n"
		)
	]
	_check(_has(missing, "ASSET_MISSING"), "a visual that does not exist")
	var present := [
		_floor(0, ["#####", "#E.c#", "#####"], "[legend]\nc = chest asset=res://assets/icon.svg\n")
	]
	_check(not _has(present, "ASSET_MISSING"), "...and one that does is fine")
	var typo := [_floor(0, ["#####", "#E.c#", "#####"], "[legend]\nc = chest loott=a\n")]
	_check(_has(typo, "UNKNOWN_PROP"), "a misspelt property is a warning")
	for i in _issues(typo):
		if i["code"] == "UNKNOWN_PROP":
			_check(i["severity"] == "warning", "...only a warning")
	var special := [_floor(0, ["#####", "#E.c#", "#####"], "[legend]\nc = chest custom.glow=blue\n")]
	_check(not _has(special, "UNKNOWN_PROP"), "a custom.* property passes")


func _check_terrain_and_cells() -> void:
	var plan := _plan_of(
		[
			_floor(
				0,
				["#######", "#Ei~:_#", "#######"],
				"[tiles]\nC2 note=hello\nB2 facing=N\n[zones]\nz tags=a rect=B2:C2\n"
			)
		]
	)
	_check(plan.issues.is_empty(), "the viewer's terrain characters read clean")
	_check(plan.is_floor(Vector3i(2, 0, 1)), "ice is floor")
	_check(plan.tile_props[Vector3i(2, 0, 1)]["surface"] == "ice", "...and says so")
	_check(plan.water_tiles.has(Vector3i(3, 0, 1)) and not plan.is_floor(Vector3i(3, 0, 1)), "~ is water, not floor")
	_check(plan.hole_tiles.has(Vector3i(4, 0, 1)), ": is a hole")
	_check(plan.wall_tiles.has(Vector3i(0, 0, 1)), "# is a wall")
	_check(not plan.wall_tiles.has(Vector3i(5, 0, 1)), "_ is empty, not a wall")
	_check(plan.tile_props[Vector3i(2, 0, 1)]["note"] == "hello", "a cell name addresses a tile")
	_check(plan.tile_props[Vector3i(1, 0, 1)]["facing"] == Vector3i(0, 0, -1), "facing is a direction")
	_check(plan.has_tag(Vector3i(1, 0, 1), "a") and plan.has_tag(Vector3i(2, 0, 1), "a"), "...in a zone rect too")
	var kinds := preload("res://scripts/dungeon/dungeon_kinds.gd")
	_check(kinds.parse_tile("AB24", 3) == Vector3i(27, 3, 23), "AB24 is column 27, row 23, from 0")
	_check(kinds.parse_tile("F25@-1", 0) == Vector3i(5, -1, 24), "@ names the storey")
	_check(kinds.parse_tile("1,2,3", 0) == Vector3i(1, 2, 3), "x,y,z")
	_check(kinds.parse_tile("A0", 0) == null and kinds.parse_tile("zz", 0) == null, "not a tile")
	# A wall on an upper storey is solid; empty space over ground is a drop.
	var ground := _floor(0, ["#####", "#...#", "#####"])
	var walled := [ground, _floor(1, ["#####", "#E.##", "#####"])]
	var open := [ground, _floor(1, ["#####", "#E. #", "#####"])]
	_check(_has(walled, "UNREACHABLE"), "a wall over ground is no way down")
	_check(not _has(open, "UNREACHABLE"), "...empty space over ground is")
	# A cracked wall is crossed one way only when it says so.
	var wall := _floor(0, ["#######", "#E.#..#", "#######"], "[tiles]\n3,1 cracked_wall axis=%s\n")
	_check(not _has([wall % "ew"], "UNREACHABLE"), "a cracked wall crossed east-west")
	_check(_has([wall % "ns"], "UNREACHABLE"), "...not when it is crossed north-south")


func _check_water() -> void:
	var legend := "[legend]\n= = bridge over=water\n"
	var rules := {"water": {"emerge": "B2"}}
	var bridge := [_floor(0, ["#######", "#E==.X#", "#######"], legend)]
	_check(_has(bridge, "WATER_NO_EMERGE"), "a bridge over water needs an emerge tile too")
	var lake := [_floor(0, ["#######", "#E~.X##", "#######"])]
	_check(_has(lake, "WATER_NO_EMERGE"), "water with no emerge tile")
	_check(not _has(lake, "WATER_NO_EMERGE", rules), "...and with one")
	_check(_has(lake, "WATER_EMERGE_NOT_FLOOR", {"water": {"emerge": "C2"}}), "an emerge tile on water")
	_check(_has(lake, "UNREACHABLE", rules), "water is not walked into: the far bank is cut off")
	var spanned := [_floor(0, ["#######", "#E==.X#", "#######"], legend)]
	_check(not _has(spanned, "UNREACHABLE", rules), "a bridge over water joins both banks")
	_check(not _has(spanned, "BRIDGE_NO_GAP", rules), "...water being what it spans")
	_check(not _has(spanned, "WATER_NO_WAY_BACK", rules), "a fall into the water comes back to the entrance")
	var stranded := [_floor(0, ["#######", "#E==.X#", "#######", "#.#####"], legend)]
	_check(_has(stranded, "WATER_NO_WAY_BACK", {"water": {"emerge": "B4"}}), "...unless it emerges somewhere cut off")
	var above := [
		_floor(0, ["#######", "#E~~.##", "#######"]),
		_floor(1, ["#######", "#.E=.##", "#######"], "[legend]\n= = bridge over=void\n"),
	]
	_check(not _has(above, "BRIDGE_NO_GAP", {"water": {"emerge": "B2@0"}}), "a bridge over water on the floor below")


func _check_exits() -> void:
	var bare := [_floor(0, ["#####", "#E.X#", "#####"])]
	_check(_has(bare, "EXIT_NO_EDGE"), "an exit with no edge is reported")
	_check(_has(bare, "ENTRANCE_NO_FACING"), "an entrance with no facing too")
	var good := [
		_floor(
			0,
			["#####", "#E.X#", "#####"],
			"[tiles]\nB2 facing=E exit_edge=W\nD2 exit_edge=E\n"
		)
	]
	_check(_codes(good).is_empty(), "an exit across a wall is fine")
	var inside := [_floor(0, ["#####", "#E.X#", "#####"], "[tiles]\nB2 facing=E exit_edge=E\nD2 exit_edge=E\n")]
	_check(_has(inside, "EXIT_EDGE_INSIDE"), "an exit that leads onto floor is not an exit")


func _check_waivers_and_rules() -> void:
	var cut := [_floor(0, ["#########", "#E..#..##", "#########"])]
	var all := {"waive": {"UNREACHABLE": "work in progress"}}
	_check(not _issues(cut).is_empty() and Validator.error_count(_issues(cut)) > 0, "an unreachable pocket is an error")
	_check(Validator.error_count(_issues(cut, all)) == 0, "a waiver turns it into a warning")
	var waived: Dictionary = _issues(cut, all)[0]
	_check(waived.get("waived", "") == "work in progress", "...that carries its reason")
	_check(Validator.format_issue(waived).contains("work in progress"), "...and prints it")
	var here := {"waive": {"UNREACHABLE:F2": "by place"}}
	_check(Validator.error_count(_issues(cut, {"waive": {"UNREACHABLE:F2": "x"}})) == 0, "a waiver by place")
	_check(Validator.error_count(_issues(cut, {"waive": {"UNREACHABLE:A1": "x"}})) > 0, "...another place does not waive it")
	_check(_has(cut, "WAIVER_UNUSED", {"waive": {"BOTTOMLESS_HOLE": "x"}}), "a waiver that matches nothing is reported")
	_check(here.size() == 1, "(fixture)")
	var spawns := [_floor(0, ["#####", "#Es.#", "#####"], "[legend]\ns = rival_spawn\n")]
	_check(_has(spawns, "SPAWN_POINTS_SHORT", {"spawn_at_entry": {"rivals": 2}}), "more rivals than spawn points")
	_check(not _has(spawns, "SPAWN_POINTS_SHORT", {"spawn_at_entry": {"rivals": 1}}), "...and exactly enough")


## Every dungeon committed under data/dungeons/ validates without an error — the same bar CI
## sets with tools/validate_dungeons.sh, so that a broken map is caught by the checks too.
func _check_committed_dungeons() -> void:
	for slug in Parser.slugs():
		var plan := Parser.load_slug(slug)
		var issues := Validator.new().validate(plan, GameData.dungeon(slug))
		var errors: Array = []
		for i in issues:
			if i["severity"] == "error":
				errors.append(Validator.format_issue(i))
		_check(errors.is_empty(), "%s: no validator error %s" % [slug, errors])
		_check(not plan.floor_tiles.is_empty() and plan.has_entrance, "%s: has floor and an entrance" % slug)
