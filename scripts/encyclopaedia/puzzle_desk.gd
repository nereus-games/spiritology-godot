## The assembly desk of the encyclopaedia, as pure logic ("Page Assembly / Fragment Manipulation").
##
## Two areas: the NEW area, where gathered fragments lie inert and stick to nothing, and the
## manipulation area, a grid of `desk_size` tiles where a fragment is moved one tile at a time,
## turned a quarter at a time, and snaps to others. Every fragment is a square of `fragment_size`
## tiles (the doc says at least 4 x 4). There is no view here, no GameSession and no signal: each
## request returns a result object (puzzle_results.gd) that a view reads. Smooth movement is the
## view's business; the desk only knows the tile a fragment ends on.
##
## Rules, in the doc's terms:
## - A fragment never overlaps another on the desk, and never leaves it. A request that would
##   do so is refused and changes nothing.
## - After each request, if a moved fragment lies less than SNAP_DISTANCE tiles from another one
##   (in the gap between their facing sides AND in how far they are off alignment) and the two
##   facing sides are of complementary shape, they snap.
## - The snap is OK only if neither is parasitic, they truly are neighbours on the page in the
##   same orientation, and the merged shape would leave no hole. Otherwise it is PARASITIC,
##   MISMATCH or HOLE, in that order of precedence; parasites vanish, the correct fragments become
##   damaged (or, already damaged, risk destruction), and what was moved is pushed back.
## - OK snaps bond the two (and so their groups); a group moves and turns as one.
## - Handling a fragment stains it, see `tick_handling`.
## - A complete page (every correct fragment present and in one group) loses its parasites
##   silently and is cleaned and repaired.
##
## A request sets off at most one snap. That is a simplification: a piece dropped between two
## neighbours bonds with one now and the other on its next move.
##
## The desk consumes fragment ids as opaque values (ints or StringNames, anything usable as a
## Dictionary key), so the page model can name fragments as it likes; see docs/architecture.md.
extends RefCounted

const Edges := preload("res://scripts/encyclopaedia/puzzle_edges.gd")
const Fragment := preload("res://scripts/encyclopaedia/puzzle_fragment.gd")
const Results := preload("res://scripts/encyclopaedia/puzzle_results.gd")

## The doc: "each fragment takes at least 4 x 4 tiles".
const MIN_FRAGMENT_SIZE := 4
## Two fragments "separated by less than 2 tiles" snap.
const SNAP_DISTANCE := 2

## The manipulation area, in tiles.
var desk_size: Vector2i
## Side of a fragment, in tiles.
var fragment_size: int
## Draws the page's sides and the destruction rolls; seed it for a reproducible desk.
var rng := RandomNumberGenerator.new()
## Where the tunable figures are read from (`puzzle_*`).
var balance: BalanceData = BalanceData.current()

## True once the page was completed.
var complete: bool = false

var _fragments := {}  # id -> Fragment, in insertion order
var _bonds := {}  # id -> {other id: true}
var _known_correct := {}  # id -> true, every correct fragment the page has, destroyed or not

# --------------------------------------------------------------------------
# Building the desk
# --------------------------------------------------------------------------


func _init(
	desk_tiles: Vector2i = Vector2i(24, 16),
	fragment_tiles: int = MIN_FRAGMENT_SIZE,
	seed_value := 0
) -> void:
	desk_size = desk_tiles
	fragment_size = maxi(fragment_tiles, MIN_FRAGMENT_SIZE)
	rng.seed = seed_value


## Fills the new fragment area with a generated page of `cols` x `rows` correct fragments and
## `parasites` parasitic ones. Ids are ints: the correct ones are `y * cols + x`, the parasites
## follow. For a real page, use `add_correct` and `add_parasite` with the page model's ids.
func generate_page(cols: int, rows: int, parasites: int) -> void:
	var edges := Edges.generate(cols, rows, rng)
	for y in rows:
		for x in cols:
			add_correct(y * cols + x, Vector2i(x, y), edges[Vector2i(x, y)])
	for i in parasites:
		add_parasite(cols * rows + i, Edges.random_edges(rng))


## Puts a correct fragment into the new fragment area: `page_cell` is where it belongs on the
## page, in fragments; `edges` its four sides as drawn on the page (puzzle_edges.gd). Adding an
## id again, after its fragment was destroyed, is how an IFP obtained anew comes back.
func add_correct(id: Variant, page_cell: Vector2i, edges: PackedInt32Array) -> void:
	var fragment := _add(id, edges)
	fragment.page_cell = page_cell
	_known_correct[id] = true


## Puts a parasitic fragment into the new fragment area.
func add_parasite(id: Variant, edges: PackedInt32Array) -> void:
	_add(id, edges)


func _add(id: Variant, edges: PackedInt32Array) -> Fragment:
	assert(not _fragments.has(id), "fragment id already on the desk")
	var fragment := Fragment.new()
	fragment.id = id
	fragment.edges = edges
	_fragments[id] = fragment
	return fragment


# --------------------------------------------------------------------------
# Asking the desk
# --------------------------------------------------------------------------


func has_fragment(id: Variant) -> bool:
	return _fragments.has(id)


## The fragment's state, or null. Read it; change it only through the requests below.
func fragment(id: Variant) -> Fragment:
	return _fragments.get(id)


## Every fragment's id still present, in the order they were added.
func ids() -> Array:
	return _fragments.keys()


## The fragments that move together with `id`, itself included, in the order they were added.
func group_of(id: Variant) -> Array:
	if not _fragments.has(id):
		return []
	var seen := {id: true}
	var queue := [id]
	while not queue.is_empty():
		var current = queue.pop_back()
		for other in _bonds.get(current, {}):
			if not seen.has(other):
				seen[other] = true
				queue.append(other)
	var group := []
	for key in _fragments:
		if seen.has(key):
			group.append(key)
	return group


## The tiles a fragment covers on the desk.
func rect_of(id: Variant) -> Rect2i:
	var f: Fragment = _fragments[id]
	return Rect2i(f.position, Vector2i(fragment_size, fragment_size))


## Correct fragments that count as correctly arranged: those bonded to at least one other
## (a page of a single fragment counts its fragment).
func arranged_count() -> int:
	var count := 0
	for id in _fragments:
		if _fragments[id].is_parasitic():
			continue
		if group_of(id).size() > 1 or _known_correct.size() == 1:
			count += 1
	return count


## Page completion, 0..1: arranged fragments over the page's total, destroyed ones included.
func completion() -> float:
	if _known_correct.is_empty():
		return 0.0
	return float(arranged_count()) / float(_known_correct.size())


# --------------------------------------------------------------------------
# Requests
# --------------------------------------------------------------------------


## Takes a fragment out of the new fragment area and puts it on the desk with its top-left tile
## at `tile`. Refused if any of it would fall outside the desk or over another fragment. It may
## snap, and if that snap is incorrect it ends back in the new area.
func place(id: Variant, tile: Vector2i) -> Results.MoveResult:
	var result := Results.MoveResult.new()
	if not _fragments.has(id):
		result.blocked = Results.MoveResult.Blocked.UNKNOWN_FRAGMENT
		return result
	var f: Fragment = _fragments[id]
	if f.area != Fragment.Area.NEW:
		result.blocked = Results.MoveResult.Blocked.NOT_ON_DESK
		return result
	var states := {id: {"area": Fragment.Area.DESK, "position": tile, "rotation": f.rotation}}
	_apply(id, [id], states, result)
	return result


## Moves the fragment, and everything bonded to it, one tile in an orthogonal direction
## (Vector2i.LEFT, RIGHT, UP or DOWN).
func move(id: Variant, direction: Vector2i) -> Results.MoveResult:
	var result := Results.MoveResult.new()
	if not _fragments.has(id):
		result.blocked = Results.MoveResult.Blocked.UNKNOWN_FRAGMENT
		return result
	if absi(direction.x) + absi(direction.y) != 1:
		result.blocked = Results.MoveResult.Blocked.BAD_DIRECTION
		return result
	if _fragments[id].area != Fragment.Area.DESK:
		result.blocked = Results.MoveResult.Blocked.NOT_ON_DESK
		return result
	var group := group_of(id)
	var states := {}
	for member in group:
		var f: Fragment = _fragments[member]
		states[member] = {
			"area": Fragment.Area.DESK, "position": f.position + direction, "rotation": f.rotation
		}
	_apply(id, group, states, result)
	return result


## Turns the fragment, and everything bonded to it, a quarter turn. A group turns about the
## top-left corner of its bounding box. In the new fragment area a fragment simply turns.
func rotate_fragment(id: Variant, clockwise: bool = true) -> Results.MoveResult:
	var result := Results.MoveResult.new()
	if not _fragments.has(id):
		result.blocked = Results.MoveResult.Blocked.UNKNOWN_FRAGMENT
		return result
	var f: Fragment = _fragments[id]
	var turn := 1 if clockwise else -1
	if f.area == Fragment.Area.NEW:
		f.rotation = posmod(f.rotation + turn, 4)
		return result
	var group := group_of(id)
	var box := rect_of(group[0])
	for member in group:
		box = box.merge(rect_of(member))
	var states := {}
	for member in group:
		var m: Fragment = _fragments[member]
		var rel := m.position - box.position
		var turned: Vector2i
		if clockwise:
			turned = Vector2i(box.size.y - rel.y - fragment_size, rel.x)
		else:
			turned = Vector2i(rel.y, box.size.x - rel.x - fragment_size)
		states[member] = {
			"area": Fragment.Area.DESK,
			"position": box.position + turned,
			"rotation": posmod(m.rotation + turn, 4)
		}
	_apply(id, group, states, result)
	return result


## Sends a lone fragment back to the new fragment area. Refused (false) for a fragment bonded
## to others or not on the desk.
func return_to_new_area(id: Variant) -> bool:
	if not _fragments.has(id) or _fragments[id].area != Fragment.Area.DESK:
		return false
	if group_of(id).size() > 1:
		return false
	_fragments[id].area = Fragment.Area.NEW
	return true


## Records `seconds` of handling on the fragment and its group: the stain spreads at the
## balance's `puzzle_stain_rate`, up to `puzzle_stain_max`. Call it while the player holds a
## fragment. A completed page no longer stains.
func tick_handling(id: Variant, seconds: float) -> void:
	if complete:
		return
	for member in group_of(id):
		var f: Fragment = _fragments[member]
		f.stain = minf(f.stain + balance.puzzle_stain_rate * seconds, balance.puzzle_stain_max)


# --------------------------------------------------------------------------
# Applying a request
# --------------------------------------------------------------------------


## Checks that `states` (id -> {area, position, rotation}, for every member of `group`) is a
## legal arrangement, applies it, and lets the moved fragments snap. `mover` is the id the
## player handled.
func _apply(mover: Variant, group: Array, states: Dictionary, result: Results.MoveResult) -> void:
	var blocked := _blocked_by(group, states)
	if blocked != Results.MoveResult.Blocked.NONE:
		result.blocked = blocked
		return
	var before := {}
	for member in group:
		var f: Fragment = _fragments[member]
		before[member] = {"area": f.area, "position": f.position, "rotation": f.rotation}
		_set_state(f, states[member])
	var snap := _snap(mover, group)
	if snap == null:
		return
	if snap.reason != Results.SnapResult.Reason.OK:
		for member in group:
			if _fragments.has(member):
				_set_state(_fragments[member], before[member])
				snap.pushed_back = true
	result.snaps.append(snap)


func _set_state(f: Fragment, state: Dictionary) -> void:
	f.area = state["area"]
	f.position = state["position"]
	f.rotation = state["rotation"]


## Why `states` is not a legal arrangement for `group`, or NONE.
func _blocked_by(group: Array, states: Dictionary) -> Results.MoveResult.Blocked:
	var area := Rect2i(Vector2i.ZERO, desk_size)
	var rects := []
	for member in group:
		var rect := Rect2i(states[member]["position"], Vector2i(fragment_size, fragment_size))
		if not area.encloses(rect):
			return Results.MoveResult.Blocked.OUT_OF_AREA
		rects.append(rect)
	for other in _fragments:
		if group.has(other) or _fragments[other].area != Fragment.Area.DESK:
			continue
		var other_rect := rect_of(other)
		for rect in rects:
			if rect.intersects(other_rect):
				return Results.MoveResult.Blocked.OVERLAP
	return Results.MoveResult.Blocked.NONE


# --------------------------------------------------------------------------
# Snapping
# --------------------------------------------------------------------------


## Looks for the snap `group` (just moved) sets off, resolves it, and returns it, or null.
## Among several candidates, the nearest is taken; an OK one beats an incorrect one at any
## distance, so that a piece never punishes the player while a right neighbour is in reach.
func _snap(mover: Variant, group: Array) -> Results.SnapResult:
	var candidates := _candidates(group)
	if candidates.is_empty():
		return null
	var chosen: Dictionary = candidates[0]
	for candidate in candidates:
		candidate["reason"] = _verdict(candidate, group)
	for candidate in candidates:
		if candidate["reason"] == Results.SnapResult.Reason.OK:
			chosen = candidate
			break
	var result := Results.SnapResult.new()
	result.reason = chosen["reason"]
	result.a = chosen["m"]
	result.b = chosen["o"]
	result.mover = mover
	if result.reason == Results.SnapResult.Reason.OK:
		_bond(chosen, group)
		if _is_page_complete():
			_complete(result)
	else:
		_punish(result)
	return result


## Every pair (m in `group`, o elsewhere on the desk) whose facing sides lie close enough and
## fit, nearest first. Each is {m, o, side (of m), shift (what to move the group by), distance}.
func _candidates(group: Array) -> Array:
	var found := []
	var size := fragment_size
	for m_id in group:
		var m: Fragment = _fragments[m_id]
		for o_id in _fragments:
			var o: Fragment = _fragments[o_id]
			if o.area != Fragment.Area.DESK or group.has(o_id):
				continue
			for side in [Edges.NORTH, Edges.EAST, Edges.SOUTH, Edges.WEST]:
				var gap: int
				var off: int
				var shift: Vector2i
				match side:
					Edges.EAST:
						gap = o.position.x - (m.position.x + size)
						off = o.position.y - m.position.y
						shift = Vector2i(gap, off)
					Edges.WEST:
						gap = m.position.x - (o.position.x + size)
						off = o.position.y - m.position.y
						shift = Vector2i(-gap, off)
					Edges.SOUTH:
						gap = o.position.y - (m.position.y + size)
						off = o.position.x - m.position.x
						shift = Vector2i(off, gap)
					_:
						gap = m.position.y - (o.position.y + size)
						off = o.position.x - m.position.x
						shift = Vector2i(off, -gap)
				if gap < 0 or gap >= SNAP_DISTANCE or absi(off) >= SNAP_DISTANCE:
					continue
				var mine := Edges.side_signature(m.edges, m.rotation, side)
				var theirs := Edges.side_signature(o.edges, o.rotation, Edges.opposite(side))
				if Edges.compatible(mine, theirs):
					found.append(
						{
							"m": m_id,
							"o": o_id,
							"side": side,
							"shift": shift,
							"distance": gap + absi(off)
						}
					)
	# Insertion sort on distance: stable, so ties keep the order the fragments were added in
	# (Array.sort_custom is not stable).
	var sorted := []
	for candidate in found:
		var index := sorted.size()
		while index > 0 and sorted[index - 1]["distance"] > candidate["distance"]:
			index -= 1
		sorted.insert(index, candidate)
	return sorted


func _verdict(candidate: Dictionary, group: Array) -> Results.SnapResult.Reason:
	var m: Fragment = _fragments[candidate["m"]]
	var o: Fragment = _fragments[candidate["o"]]
	if m.is_parasitic() or o.is_parasitic():
		return Results.SnapResult.Reason.PARASITIC
	if not _truly_match(m, o, candidate["side"]):
		return Results.SnapResult.Reason.MISMATCH
	if _leaves_hole(group, candidate["shift"], candidate["o"]):
		return Results.SnapResult.Reason.HOLE
	return Results.SnapResult.Reason.OK


## Whether `o`, which lies beyond `side` of `m`, is the fragment that belongs there on the page:
## both turned alike, and `o`'s page cell next to `m`'s in the direction `side` points to once
## the turn is undone.
func _truly_match(m: Fragment, o: Fragment, side: int) -> bool:
	if m.rotation != o.rotation:
		return false
	var page_side := posmod(side - m.rotation, 4)
	return o.page_cell - m.page_cell == Edges.STEP[page_side]


## Whether snapping `group` by `shift` against `other_id`'s group cannot be done cleanly: the
## moved group would not fit (it falls outside the desk or onto a third fragment), or the merged
## shape would enclose empty tiles.
func _leaves_hole(group: Array, shift: Vector2i, other_id: Variant) -> bool:
	var area := Rect2i(Vector2i.ZERO, desk_size)
	var other_group := group_of(other_id)
	var tiles := {}
	for member in group:
		var rect := rect_of(member)
		rect.position += shift
		if not area.encloses(rect):
			return true
		for other in _fragments:
			if group.has(other) or _fragments[other].area != Fragment.Area.DESK:
				continue
			if rect.intersects(rect_of(other)):
				return true
		_add_tiles(tiles, rect)
	for member in other_group:
		_add_tiles(tiles, rect_of(member))
	return _has_cavity(tiles)


func _add_tiles(tiles: Dictionary, rect: Rect2i) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			tiles[Vector2i(x, y)] = true


## Whether the set of tiles encloses an empty tile: one that cannot be reached from outside its
## bounding box by 4-connected steps through empty tiles.
func _has_cavity(tiles: Dictionary) -> bool:
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-(1 << 30), -(1 << 30))
	for tile in tiles:
		lo = Vector2i(mini(lo.x, tile.x), mini(lo.y, tile.y))
		hi = Vector2i(maxi(hi.x, tile.x), maxi(hi.y, tile.y))
	lo -= Vector2i.ONE
	hi += Vector2i.ONE
	var reached := {lo: true}
	var stack: Array[Vector2i] = [lo]
	while not stack.is_empty():
		var tile: Vector2i = stack.pop_back()
		for step in Edges.STEP:
			var next: Vector2i = tile + step
			if next.x < lo.x or next.y < lo.y or next.x > hi.x or next.y > hi.y:
				continue
			if tiles.has(next) or reached.has(next):
				continue
			reached[next] = true
			stack.append(next)
	# Every tile of the expanded box is a tile of the shape or was reached, unless enclosed.
	return reached.size() + tiles.size() < (hi.x - lo.x + 1) * (hi.y - lo.y + 1)


## Moves the group flush and aligned against the other fragment, and bonds the pair.
func _bond(candidate: Dictionary, group: Array) -> void:
	for member in group:
		_fragments[member].position += candidate["shift"]
	var m = candidate["m"]
	var o = candidate["o"]
	if not _bonds.has(m):
		_bonds[m] = {}
	if not _bonds.has(o):
		_bonds[o] = {}
	_bonds[m][o] = true
	_bonds[o][m] = true


## The consequences of an incorrect snap on the two fragments that met.
func _punish(result: Results.SnapResult) -> void:
	for id in [result.a, result.b]:
		var f: Fragment = _fragments[id]
		if f.is_parasitic():
			_remove(id)
			result.parasites_removed.append(id)
		elif not f.damaged:
			f.damaged = true
			result.damaged.append(id)
		elif rng.randf() < balance.puzzle_destroy_chance:
			_remove(id)
			result.destroyed.append(id)


func _remove(id: Variant) -> void:
	_fragments.erase(id)
	for other in _bonds.get(id, {}):
		_bonds[other].erase(id)
	_bonds.erase(id)


# --------------------------------------------------------------------------
# Completion
# --------------------------------------------------------------------------


## Whether every correct fragment of the page is present and in a single group.
func _is_page_complete() -> bool:
	if _known_correct.is_empty():
		return false
	for id in _known_correct:
		if not _fragments.has(id):
			return false
	return group_of(_known_correct.keys()[0]).size() == _known_correct.size()


## 100 %: parasites go without a sound, damage and stain are repaired.
func _complete(result: Results.SnapResult) -> void:
	complete = true
	result.completed = true
	for id in _fragments.keys():
		var f: Fragment = _fragments[id]
		if f.is_parasitic():
			_remove(id)
			result.parasites_cleared.append(id)
		else:
			f.damaged = false
			f.stain = 0.0
