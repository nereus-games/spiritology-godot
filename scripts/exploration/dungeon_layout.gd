## A dungeon's LAYOUT: what level design lays down and the game does not change — the floor, the
## holes and pits, the walls the grid implies, and the entrance and exits. What happens ON the
## layout (who stands where, which mechanism sits on which tile, whose turn it is) stays with the
## [DungeonManager].
##
## The line is the one the authoring format will need: a layout is what gets declared, loaded and
## checked against the design doc's level-design rules, and an authored dungeon will fill this
## object rather than call a builder tile by tile. Today it is still filled tile by tile, by
## code-built scenarios.
##
## Held by the [DungeonManager] as [member DungeonManager.layout], like
## [member DungeonManager.safe_areas]: a member rather than methods of a manager that is big
## enough already.
##
## No `class_name` (the CLI class-cache trap): preloaded.
extends RefCounted

const NEIGHBOURS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)
]

var _dungeon

# Walkable tiles (floor). tile:Vector3i -> true.
var _floor: Dictionary = {}

# Tiles rendered as wall blocks, remembered by [method remember_walls]. The mini-map draws them:
# a room reads by its outline, not only by the absence of floor.
var _walls: Dictionary = {}

# Tiles explicitly left EMPTY — a deliberate hole from the level design. Never rendered as a
# wall, even with nothing holding them up. Entering one is a BOTTOMLESS fall, and fatal (see
# [method is_bottomless]). A merely absent tile still becomes a wall: that is the normal case
# around the outside of a room.
var _hole: Dictionary = {}

# Pit tiles (a floor set LOWER, a ravine): rendered as a lowered dark slab, never as a wall,
# and with no normal slab when the tile is walkable too — that is the bridge plank laid over
# it. Gives the "log over a drop" look.
var _pit: Dictionary = {}

# Per the design doc ("Dungeons"), you leave a dungeon by reaching an EXIT and interacting
# with it, and "the dungeon entry counts as an exit point". These tiles are declared by level
# design — in dev, by the test scenario. Today they serve the mechanisms that send the player
# back to them, such as dieverting.
# ## TODO: leaving the dungeon proper — the exit interaction, and a world map to return to — is
# still unwired. A devitalised duo does leave, for the scenario picker; see `exploration.gd`.
var _entrance: Vector3i
var _has_entrance := false
var _exits: Array[Vector3i] = []


func _init(dungeon) -> void:
	_dungeon = dungeon


# --------------------------------------------------------------------------
# Floor, holes and pits
# --------------------------------------------------------------------------


func is_floor(tile: Vector3i) -> bool:
	return _floor.has(tile)


func set_floor_tiles(tiles: Array) -> void:
	_floor.clear()
	for c in tiles:
		_floor[c] = true


func add_floor(tile: Vector3i) -> void:
	_floor[tile] = true


## Takes a tile out of the floor: a pillar, the shaft a flight of stairs climbs through.
func remove_floor(tile: Vector3i) -> void:
	_floor.erase(tile)


## The floor tiles (tile -> true). Read-only: this is the live dictionary.
func floor_tiles() -> Dictionary:
	return _floor


## Marks a tile as a pit: walkable, but [method DungeonManager.render_grid] lays NEITHER a normal
## slab NOR a wall there — the tile is held up only by whatever level design puts on it, a bridge
## plank. With no real floor underneath, a dark slab is laid below so the gap does not read as a
## void; otherwise the floor below serves as the bottom.
func mark_pit(tile: Vector3i) -> void:
	_pit[tile] = true


## Tiles marked as pits (tile -> true). Read-only: this is the live dictionary.
func pit_tiles() -> Dictionary:
	return _pit


## Marks a tile as an outright hole: no wall to plug it, and no bottom either.
func mark_hole(tile: Vector3i) -> void:
	_hole[tile] = true


func is_hole(tile: Vector3i) -> bool:
	return _hole.has(tile)


## Whether entering this tile means a BOTTOMLESS fall. Such a fall should not exist — it would
## be a level-design mistake — because the outside of a room is rendered as wall precisely
## since nothing holds it up. If level design leaves one anyway, it is treated as what it is,
## a floor too far down to survive: a fatal fall, rather than a silent block.
func is_bottomless(tile: Vector3i) -> bool:
	return _hole.has(tile) and not _floor.has(tile) and fall_landing(tile) == tile


## Where a fall from `tile` lands: the first FLOOR tile below it. Returns `tile` unchanged
## when there is none, which means no fall at all — a wall.
func fall_landing(tile: Vector3i) -> Vector3i:
	for level in range(tile.y - 1, tile.y - 12, -1):
		var below := Vector3i(tile.x, level, tile.z)
		if _floor.has(below):
			return below
	return tile


# --------------------------------------------------------------------------
# Walls
# --------------------------------------------------------------------------


## Works out the walls the grid implies and keeps them for [method wall_tiles] and
## [method is_wall]; returns them. Called by [method DungeonManager.render_grid].
func remember_walls() -> Dictionary:
	_walls = derive_wall_tiles()
	return _walls


## Tiles rendered as wall blocks. Empty until [method remember_walls] has run.
func wall_tiles() -> Dictionary:
	return _walls


func is_wall(tile: Vector3i) -> bool:
	return _walls.has(tile)


## TODO (2026-09-02) — AUTHORING DEBT. Walls and holes are today DERIVED from the floor grid
## alone: a wall is "nothing here, and nothing below", and an outright hole only exists if
## someone calls [method mark_hole] — nobody does, outside the headless check. Two rules from
## the design doc therefore rest on inference rather than declaration:
##  - "a wall can serve as ground on the floor above it" (no slab above a wall);
##  - "if an endless fall happens anyway, it devitalises" (the outright hole).
## Once a dungeon authoring format exists, walls and holes will have to be DECLARED the way
## floors are, and [method derive_wall_tiles] will be scaffolding for code-built test
## scenarios only.
##
## Tiles rendered as wall blocks: non-floor tiles next to floor, carrying no mechanism and no
## pit, with no floor below them — the lip of a drop stays open rather than being walled off.
##
## Public because it is a query on the MODEL ("where does the grid imply a wall?") rather than
## a rendering matter: the geometry checks assert against it.
func derive_wall_tiles() -> Dictionary:
	var wall_tiles := {}
	for c in _floor:
		for d in NEIGHBOURS:
			var n: Vector3i = c + d
			if _hole.has(n):
				continue  # a deliberate hole: on no account wall it off
			if (
				not _floor.has(n)
				and _dungeon.mechanisms_at(n).is_empty()
				and not _pit.has(n)
				and fall_landing(n) == n
			):
				wall_tiles[n] = true
	return wall_tiles


# --------------------------------------------------------------------------
# Entrance & exits
# --------------------------------------------------------------------------


## Declares the entrance tile. It ALSO counts as an exit, per the design doc, so there is no
## need to add it twice.
func set_entrance(tile: Vector3i) -> void:
	_entrance = tile
	_has_entrance = true
	add_exit(tile)


func has_entrance() -> bool:
	return _has_entrance


## The dungeon's entrance tile — Vector3i.ZERO while none has been declared, so check
## [method has_entrance] before using it.
func entrance_tile() -> Vector3i:
	return _entrance


func add_exit(tile: Vector3i) -> void:
	if tile not in _exits:
		_exits.append(tile)


func exit_tiles() -> Array[Vector3i]:
	return _exits.duplicate()


func has_exit() -> bool:
	return not _exits.is_empty()


## A random exit — the design doc says "at random if more than one". Returns Vector3i.ZERO
## when none is declared, so check [method has_exit] first.
func random_exit() -> Vector3i:
	if _exits.is_empty():
		return Vector3i.ZERO
	return _exits[randi() % _exits.size()]
