## Looking for tiles around a dungeon: a free one near a given tile, the ones reachable on
## foot, a random one to be teleported to. Questions the grid answers without changing it, which
## actors, spawners and mechanisms all need and none of them owns.
##
## Held by the [DungeonManager] as [member DungeonManager.tile_search], like
## [member DungeonManager.safe_areas]: a member rather than methods of a manager that is big
## enough already. It reads the dungeon through that manager's public queries.
##
## No `class_name` (the CLI class-cache trap): preloaded.
extends RefCounted

const NEIGHBOURS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)
]

var _dungeon


func _init(dungeon) -> void:
	_dungeon = dungeon


## The nearest free floor tile to `tile` (`tile` itself if it is free), for placing an actor
## without breaking the one-occupant-per-tile invariant. Returns `tile` when nothing around is
## free, and leaves the caller to decide what that means.
func free_tile_near(tile: Vector3i) -> Vector3i:
	if _dungeon.is_floor(tile) and _dungeon.occupant_at(tile) == null:
		return tile
	for d in NEIGHBOURS:
		var n: Vector3i = tile + d
		if _dungeon.is_walkable(n) and _dungeon.occupant_at(n) == null:
			return n
	return tile


## Free floor tiles AROUND `tile`, on the same floor, within `radius` tiles (Manhattan
## distance), shuffled. `tile` itself is excluded. Lets actors be spawned "nearby" without
## caring about the shape of the room.
func free_tiles_near(tile: Vector3i, radius: int) -> Array[Vector3i]:
	var found: Array[Vector3i] = []
	for dx in range(-radius, radius + 1):
		for dz in range(-radius, radius + 1):
			if absi(dx) + absi(dz) > radius or (dx == 0 and dz == 0):
				continue
			var c := tile + Vector3i(dx, 0, dz)
			if _dungeon.is_walkable(c) and _dungeon.occupant_at(c) == null:
				found.append(c)
	found.shuffle()
	return found


## How many steps it takes to walk to every tile reachable from `from` in at most `max_steps`,
## as tile -> steps (`from` itself at 0). A walk, not a flight: it goes around walls, closed
## gateways and occupied tiles, and stays on one floor — stairs and falls are not steps.
func walking_distances(from: Vector3i, max_steps: int) -> Dictionary:
	var steps := {from: 0}
	var frontier: Array[Vector3i] = [from]
	while not frontier.is_empty():
		var current: Vector3i = frontier.pop_front()
		var d: int = steps[current]
		if d >= max_steps:
			continue
		for delta in NEIGHBOURS:
			var n: Vector3i = current + delta
			if steps.has(n) or not _dungeon.can_step(current, n):
				continue
			steps[n] = d + 1
			frontier.append(n)
	return steps


## A random walkable floor tile other than `exclude`, outside every safe area when
## `avoid_safe` — where a random teleport may drop a rival. Returns `exclude` when there is none.
func random_floor_tile(exclude: Vector3i, avoid_safe := false) -> Vector3i:
	var candidates: Array = []
	for c in _dungeon.floor_tiles():
		if (
			c != exclude
			and _dungeon.is_walkable(c)
			and not (avoid_safe and _dungeon.safe_areas.has(c))
		):
			candidates.append(c)
	if candidates.is_empty():
		return exclude
	return candidates[randi() % candidates.size()]
