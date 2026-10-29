## Looking for tiles around a dungeon: a free one near a given tile, the ones reachable on
## foot, a random one to be teleported to, and making room by pushing a group off its tile.
## Which actors, spawners and mechanisms all need and none of them owns.
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


## The shortest way on foot from `from` to `to`, as the tiles to cross, both ends included. Empty
## when there is none. Two things set it apart from [method walking_distances]: occupants do not
## stand in the way (the caller decides what to do about a tile that is taken when it gets there),
## and it goes across floors, by every staircase — a tile and the one it leads to are consecutive
## in the path though they are not neighbours. Elevators and falls are not used.
##
## `avoid_safe` keeps the path out of safe areas, as a rival is kept out of them.
func shortest_path(from: Vector3i, to: Vector3i, avoid_safe := false) -> Array[Vector3i]:
	var path: Array[Vector3i] = []
	if from == to:
		return [from]
	var links := _stair_links()
	var came := {from: from}
	var frontier: Array[Vector3i] = [from]
	while not frontier.is_empty() and not came.has(to):
		var current: Vector3i = frontier.pop_front()
		var nexts: Array[Vector3i] = []
		for delta in NEIGHBOURS:
			var n: Vector3i = current + delta
			if _dungeon.is_floor(n) and not _dungeon.is_blocked_by_mechanism(n):
				if not _dungeon.is_edge_blocked(current, n):
					nexts.append(n)
		for dest in links.get(current, []):
			nexts.append(dest)
		for n in nexts:
			if came.has(n) or (avoid_safe and _dungeon.safe_areas.has(n)):
				continue
			came[n] = current
			frontier.append(n)
	if not came.has(to):
		return path
	var step := to
	while step != from:
		path.push_front(step)
		step = came[step]
	path.push_front(from)
	return path


## The staircases of the dungeon as standing tile -> the tiles taking them leads to.
func _stair_links() -> Dictionary:
	var links := {}
	for m in _dungeon.get_children():
		if not m.has_method("has_level_link") or not m.has_level_link():
			continue
		if not m.level_link_needs_step_in() or not _dungeon.is_floor(m.level_link_to()):
			continue
		var out: Array = links.get(m.level_link_from(), [])
		out.append(m.level_link_to())
		links[m.level_link_from()] = out
	return links


## A random walkable floor tile other than `exclude`, outside every safe area when
## `avoid_safe` — where a random teleport may drop a rival. Returns `exclude` when there is none.
func random_floor_tile(exclude: Vector3i, avoid_safe := false) -> Vector3i:
	var candidates: Array = []
	for c in _dungeon.layout.floor_tiles():
		if (
			c != exclude
			and _dungeon.is_walkable(c)
			and not (avoid_safe and _dungeon.safe_areas.has(c))
		):
			candidates.append(c)
	if candidates.is_empty():
		return exclude
	return candidates[randi() % candidates.size()]


## Pushes the rival `group` off its tile onto a neighbouring one, to make room for a group
## arriving through a teleport gate or spawning on its tile. The design doc's order of
## preference: an ORDINARY free tile; failing that, a trap, or a ledge with no railing to fall
## from; failing that, the group next to it is pushed in turn and this one takes its place.
## Never onto the player, and never into a safe area. `pushing` holds the groups already in the
## chain, so it cannot loop. Returns false when the group could not be moved at all.
func push_group_aside(group: Node, pushing: Dictionary = {}) -> bool:
	pushing[group] = true
	var at: Vector3i = group.tile
	var safe = _dungeon.safe_areas
	var around: Array[Vector3i] = []
	for d in NEIGHBOURS:
		var n: Vector3i = at + d
		if not _dungeon.is_edge_blocked(at, n) and n != _dungeon.player_tile() and not safe.has(n):
			around.append(n)
	# An ordinary free tile: floor, nobody on it, nothing on it.
	for n in around:
		if _dungeon.is_walkable(n) and _dungeon.mechanisms_at(n).is_empty():
			_shove(group, n)
			return true
	# A free tile carrying a mechanism — a trap, typically — which fires on arrival.
	for n in around:
		if _dungeon.is_walkable(n):
			_shove(group, n)
			_dungeon.notify_entered(n, group)
			return true
	# A ledge: no floor there, but some further down. The group falls, and takes the damage.
	for n in around:
		var landing: Vector3i = _dungeon.layout.fall_landing(n)
		if not _dungeon.is_floor(n) and landing != n and not safe.has(landing):
			if group.has_method("fall_down"):
				group.fall_down(n)
				return true
	# The group next to it, pushed in turn.
	for n in around:
		var next_group: Node = _dungeon.occupant_at(n)
		if next_group == null or pushing.has(next_group):
			continue
		if push_group_aside(next_group, pushing):
			_shove(group, n)
			return true
	return false


func _shove(group: Node, to_tile: Vector3i) -> void:
	_dungeon.release(group.tile)
	_dungeon.reserve(to_tile, group)
	group.teleport_to(to_tile)
