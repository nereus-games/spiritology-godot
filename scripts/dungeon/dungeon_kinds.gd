## What a dungeon map file may place, and with which properties.
##
## One table, read by the parser (to type the values and refuse a kind it does not know) and by
## the validator (to know which kinds are floor, which are hazards, and which property names are
## typos). The loader that turns a plan into mechanisms will read it too: a kind here is a
## mechanism script there.
##
## Property types: `bool`, `int`, `float`, `str`, `list` (comma-separated strings), `tile`
## (`x,z` on the file's own storey, or `x,y,z`), `tiles` (tiles separated by `;`), `dir`
## (N, E, S or W: north is up the page, so -z), and `enum:a|b|c`.
##
## Every kind also takes the COMMON properties below, and anything starting with `custom.`
## passes unchecked — the escape hatch for a case the table does not know yet.
##
## No `class_name` (the CLI class-cache trap): referenced by `preload`.
extends RefCounted

## Accepted by every placement and every annotated tile.
const COMMON := {
	"note": "str",  # the designer's own remark, kept and otherwise ignored
	"asset": "str",  # a specific visual, as a `res://` path
	"tags": "list",  # free tags; `unreachable_ok`, `no_teleport` and `safe` mean something to the validator
	"facing": "dir",  # which way the player looks on arriving, for the entrance
	"exit_edge": "dir",  # the border of an exit (or the entrance) the player leaves the dungeon across
}

## `floor`: "yes" — the tile is floor; "no" — it is not (a staircase is carried past, a cracked
## wall is wall); "any" — leave the tile as the grid draws it. `hazard`: may not stand in a safe
## area. `pit`: the tile is a pit, and the plank laid over it makes it walkable.
const KINDS := {
	&"trap":
	{
		"floor": "yes",
		"hazard": true,
		"props":
		{
			"type": "enum:disarray|teleport|poison",
			"reactivates": "bool",
			"revealed": "bool",
			"poison_per_turn": "int",
			"poison_turns": "int",
			"disarray_min": "int",
			"disarray_max": "int",
		},
	},
	&"chest":
	{
		"floor": "yes",
		"hazard": false,  # a trapped chest is one: see `is_hazard`
		"props":
		{
			"trapped": "bool",
			"loot": "list",
			"loot_min": "int",
			"loot_max": "int",
			"revealed": "bool",
		},
	},
	&"gate":
	{
		"floor": "any",
		"hazard": false,
		"props":
		{
			"type": "enum:automated|locked|meditation|teleport",
			"edge": "dir",
			"arrival": "tile",
			"two_sided": "bool",
			"currency": "str",
			"tier": "enum:early|late",
			"meditations": "int",
		},
	},
	&"stairs":
	{
		"floor": "no",
		"hazard": false,
		"props": {"dir": "enum:up|down", "face": "dir"},
	},
	&"lift":
	{
		"floor": "yes",
		"hazard": false,
		"props": {"path": "tiles", "linked": "tiles"},
	},
	# `over`: what lies under the plank. A fall from it lands on the floor below, or in the water
	# of the same tile (and the water gives the player back at the dungeon's emerge tile).
	&"bridge":
	{
		"floor": "yes",
		"hazard": true,
		"pit": true,
		"props": {"over": "enum:void|water"},
	},
	&"guardrail": {"floor": "any", "hazard": false, "props": {"edge": "dir"}},
	&"crumbly": {"floor": "yes", "hazard": true, "props": {"loot": "list"}},
	&"litter": {"floor": "yes", "hazard": false, "props": {"loot": "list"}},
	&"crystal": {"floor": "yes", "hazard": false, "props": {}},
	&"dieverting": {"floor": "yes", "hazard": true, "props": {}},
	# `axis`: the way the wall is crossed, `ew` between its west and east tiles. Both when absent.
	&"cracked_wall": {"floor": "no", "hazard": false, "props": {"axis": "enum:ns|ew"}},
	# A basic rival spawn point, and a spawn point of a special faction.
	&"rival_spawn": {"floor": "yes", "hazard": false, "props": {}},
	&"special_spawn": {"floor": "yes", "hazard": false, "props": {"faction": "str"}},
	# Decoration with no game effect (a column, a stone tree, a submarine). `corner`: centred on the
	# tile's top-left corner rather than on the tile.
	&"scenery":
	{
		"floor": "any",
		"hazard": false,
		"props": {"type": "str", "label": "str", "corner": "bool"},
	},
	&"decor":
	{
		"floor": "any",
		"hazard": false,
		"props": {"type": "enum:gooey_marks|posters|scratch_marks"},
	},
}

const DIRECTIONS := {
	"N": Vector3i(0, 0, -1),
	"S": Vector3i(0, 0, 1),
	"E": Vector3i(1, 0, 0),
	"W": Vector3i(-1, 0, 0),
}


## `x,z` on the storey `default_y`, `x,y,z`, or a spreadsheet cell name (`AB24`: column AB, row 24,
## counted from 1 like the viewer's grid). Either form may end in `@y` to name the storey. Null
## when it is none of those.
static func parse_tile(text: String, default_y: int):
	var s := text.strip_edges()
	var y := default_y
	var at := s.find("@")
	if at >= 0:
		var floor_part := s.substr(at + 1)
		if not floor_part.is_valid_int():
			return null
		y = floor_part.to_int()
		s = s.substr(0, at)
	var cell = cell_tile(s)
	if cell != null:
		return Vector3i(cell.x, y, cell.y)
	var parts := s.split(",")
	for part in parts:
		if not part.strip_edges().is_valid_int():
			return null
	if parts.size() == 2:
		return Vector3i(parts[0].to_int(), y, parts[1].to_int())
	if parts.size() == 3 and at < 0:
		return Vector3i(parts[0].to_int(), parts[1].to_int(), parts[2].to_int())
	return null


## (x, z) of a cell name such as `C7` or `AB24`, or null.
static func cell_tile(name: String):
	var i := 0
	var column := 0
	while i < name.length() and name.unicode_at(i) >= 65 and name.unicode_at(i) <= 90:
		column = column * 26 + name.unicode_at(i) - 64
		i += 1
	var digits := name.substr(i)
	if i == 0 or digits.is_empty() or not digits.is_valid_int() or digits.to_int() < 1:
		return null
	return Vector2i(column - 1, digits.to_int() - 1)


static func has_kind(kind: StringName) -> bool:
	return KINDS.has(kind)


## The declared type of `prop` on `kind`, or "" when the name is unknown there.
static func prop_type(kind: StringName, prop: String) -> String:
	if COMMON.has(prop):
		return COMMON[prop]
	if prop.begins_with("custom."):
		return "str"
	if KINDS.has(kind):
		return KINDS[kind]["props"].get(prop, "")
	return ""


## Whether a placement stands in the way of a safe area. A trapped chest is a hazard; a plain
## one is loot.
static func is_hazard(kind: StringName, props: Dictionary) -> bool:
	if kind == &"chest":
		return bool(props.get("trapped", false))
	return bool(KINDS.get(kind, {}).get("hazard", false))
