## A dungeon's SAFE AREAS, from the design doc's "Elevators": every area reached by elevator needs
## a safeguard against its platform being left stranded at the far end, and a safe area is one of
## them. Nothing in it can get the player devitalised — no rival, no ledge to fall from, no trap —
## and the player cannot be taken out of it against their will, so they always leave it the way
## they came in.
##
## Level design DECLARES the area ([method mark]); the game keeps rivals out of it
## ([method rival_may_enter]), and [method violations] reports whatever level design put in it
## that has no business there.
##
## Held by the [DungeonManager] as [member DungeonManager.safe_areas].
##
## No `class_name` (the CLI class-cache trap): preloaded.
extends RefCounted

const NEIGHBOURS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)
]

var _dungeon
# tile:Vector3i -> true.
var _tiles: Dictionary = {}


func _init(dungeon) -> void:
	_dungeon = dungeon


## Declares tiles as part of a safe area.
func mark(tiles: Array) -> void:
	for c in tiles:
		_tiles[c] = true


func has(tile: Vector3i) -> bool:
	return _tiles.has(tile)


## The safe tiles (tile -> true). Read-only: this is the live dictionary.
func tiles() -> Dictionary:
	return _tiles


## Whether a rival may step onto `tile`: not into a safe area, nor onto a mechanism that would
## carry it into one — an elevator, stairs.
func rival_may_enter(tile: Vector3i) -> bool:
	if _tiles.has(tile):
		return false
	for m in _dungeon.mechanisms_at(tile):
		if m.has_method("far_end") and _tiles.has(m.far_end()):
			return false
		if m.has_level_link() and _tiles.has(m.level_link_to()):
			return false
	return true


## What breaks a safe area, one line per fault, for the checks and for level design: a hazard on
## one of its tiles, an unrailed ledge on its edge, a rival spawn point inside it, a platform
## elsewhere linked to one serving it. Empty when every area holds.
func violations() -> Array[String]:
	var faults: Array[String] = []
	for c in _tiles:
		if not _dungeon.is_floor(c):
			faults.append("%s: safe tile with no floor" % c)
		for m in _dungeon.mechanisms_at(c):
			if m.is_hazard():
				faults.append("%s: hazard in a safe area (%s)" % [c, m.get_script().resource_path])
		for d in NEIGHBOURS:
			var n: Vector3i = c + d
			if _dungeon.is_floor(n) or _dungeon.is_edge_blocked(c, n):
				continue
			if _dungeon.is_bottomless(n) or _dungeon.fall_landing(n) != n:
				faults.append("%s -> %s: ledge with no railing" % [c, n])
	var config: DungeonConfig = _dungeon.config
	if config != null:
		for point in config.spawn_points:
			if _tiles.has(point):
				faults.append("%s: rival spawn point in a safe area" % point)
		for group in config.fixed_groups:
			if group != null and _tiles.has(group.tile):
				faults.append("%s: fixed rival group in a safe area" % group.tile)
	# A linked platform moves on someone else's step. It leaves its rider behind, but one serving
	# a safe area could still be taken away from it — and with it the way out.
	for m in _dungeon.get_children():
		if not ("linked" in m):
			continue
		for other in m.linked:
			if is_instance_valid(other) and (_tiles.has(other.tile) or _tiles.has(other.far_end())):
				faults.append("%s: moves a platform serving a safe area" % m.tile)
	return faults
