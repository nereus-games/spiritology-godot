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
	"tags": "list",  # free tags; `unreachable_ok` and `no_teleport` mean something to the validator
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
	&"bridge": {"floor": "yes", "hazard": true, "pit": true, "props": {}},
	&"guardrail": {"floor": "any", "hazard": false, "props": {"edge": "dir"}},
	&"crumbly": {"floor": "yes", "hazard": true, "props": {"loot": "list"}},
	&"litter": {"floor": "yes", "hazard": false, "props": {"loot": "list"}},
	&"crystal": {"floor": "yes", "hazard": false, "props": {}},
	&"dieverting": {"floor": "yes", "hazard": true, "props": {}},
	&"cracked_wall": {"floor": "no", "hazard": false, "props": {}},
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
