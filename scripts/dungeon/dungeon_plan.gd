## A dungeon as its map files describe it: what was DECLARED, before any mechanism exists.
##
## Deliberately not a [DungeonLayout]: this holds no nodes and needs no [DungeonManager], so the
## validator runs headless in milliseconds on a dungeon of any size. The loader that fills a
## manager from a plan comes later; the plan is the contract between the files and everything
## that reads them.
##
## No `class_name` (the CLI class-cache trap): referenced by `preload`.
extends RefCounted

const Kinds := preload("res://scripts/dungeon/dungeon_kinds.gd")

## The directory name, and the base of the dungeon's translation keys.
var slug: StringName = &""

## Walkable tiles. Vector3i -> true. A pit is in here only under a bridge plank.
var floor_tiles: Dictionary = {}
## Deliberate holes (`~`) and pits (`_`, or a plank's tile). Vector3i -> true.
var hole_tiles: Dictionary = {}
var pit_tiles: Dictionary = {}

var entrance := Vector3i.ZERO
var has_entrance := false
var exits: Array[Vector3i] = []

## One entry per placed thing: {kind: StringName, tile: Vector3i, props: Dictionary, source: String}.
## `props` holds typed values, except the ones the kinds table does not know, kept as strings.
var placements: Array = []

## Free notes and annotations on a bare tile: Vector3i -> props Dictionary.
var tile_props: Dictionary = {}

## Named zones: name -> {tags: Array[String], tiles: Dictionary (Vector3i -> true)}. The same
## name in several storey files is one zone.
var zones: Dictionary = {}

## What the parser itself could not read: the same shape the validator reports.
var issues: Array = []

var _by_tile: Dictionary = {}


func add_issue(severity: String, code: String, tile, source: String, args: Array = []) -> void:
	issues.append(
		{"severity": severity, "code": code, "tile": tile, "source": source, "args": args}
	)


func is_floor(tile: Vector3i) -> bool:
	return floor_tiles.has(tile)


func add_placement(kind: StringName, tile: Vector3i, props: Dictionary, source: String) -> void:
	placements.append({"kind": kind, "tile": tile, "props": props, "source": source})
	if not _by_tile.has(tile):
		_by_tile[tile] = []
	_by_tile[tile].append(placements[-1])


## The placements standing on `tile`.
func placements_at(tile: Vector3i) -> Array:
	return _by_tile.get(tile, [])


func add_zone_tile(zone: String, tags: Array, tile: Vector3i) -> void:
	if not zones.has(zone):
		zones[zone] = {"tags": [], "tiles": {}}
	for t in tags:
		if not zones[zone]["tags"].has(t):
			zones[zone]["tags"].append(t)
	zones[zone]["tiles"][tile] = true


## Whether `tile` lies in a zone carrying `tag`, or is itself tagged with it.
func has_tag(tile: Vector3i, tag: String) -> bool:
	for z in zones.values():
		if z["tiles"].has(tile) and z["tags"].has(tag):
			return true
	if tile_props.has(tile) and tile_props[tile].get("tags", []).has(tag):
		return true
	for p in placements_at(tile):
		if p["props"].get("tags", []).has(tag):
			return true
	return false


## Every tile of every zone carrying `tag`. Vector3i -> true.
func tiles_with_tag(tag: String) -> Dictionary:
	var out := {}
	for z in zones.values():
		if z["tags"].has(tag):
			out.merge(z["tiles"])
	return out


## The first floor tile below `tile`, within the engine's reach of a fall, or `tile` itself when
## there is none. Same rule as [method DungeonLayout.fall_landing].
func fall_landing(tile: Vector3i) -> Vector3i:
	for level in range(tile.y - 1, tile.y - 12, -1):
		var below := Vector3i(tile.x, level, tile.z)
		if floor_tiles.has(below):
			return below
	return tile
