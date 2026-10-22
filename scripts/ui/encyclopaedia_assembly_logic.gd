## The assembly screen's decisions, with no node in sight, so that a headless check can drive
## them: what is selected, where the cursor hops, where a fragment from the new fragment area
## enters the desk, how tiles map to pixels, how the new fragment area is laid out, what is
## reported to the session, and how the layout is saved in a page's `puzzle_state`.
##
## It wraps one [code]puzzle_desk.gd[/code] and adds nothing to its rules. See "Page Assembly /
## Fragment Manipulation" in the design doc; the rules this script invents are listed in
## docs/roadmap.md.
##
## Ids: the page's 33 true fragments are 0 to 32, laid out row by row on a page of 3 x 11
## fragments (the doc's diagram); parasitic ones are numbered from [constant FIRST_PARASITE_ID]
## upward, never reused.
##
## No `class_name` (the CLI class-cache trap): referenced by `preload`.
extends RefCounted

const Desk := preload("res://scripts/encyclopaedia/puzzle_desk.gd")
const Edges := preload("res://scripts/encyclopaedia/puzzle_edges.gd")
const Fragment := preload("res://scripts/encyclopaedia/puzzle_fragment.gd")
const Results := preload("res://scripts/encyclopaedia/puzzle_results.gd")

## A page is 3 fragments wide and 11 tall, as in the design doc's diagram.
const PAGE_COLS := 3
const PAGE_ROWS := 11
const PAGE_FRAGMENTS := PAGE_COLS * PAGE_ROWS
## Side of a fragment, in tiles: the doc's minimum.
const FRAGMENT_TILES := 4
## The manipulation area, in tiles. Wide enough for the whole page lying on its side
## (11 x 4 = 44 tiles) and a little more; a page standing up (44 tall) never needs to fit.
const DESK_TILES := Vector2i(48, 28)
const FIRST_PARASITE_ID := 100
const STATE_VERSION := 1
## No free tile for a fragment to enter the desk on.
const NO_TILE := Vector2i(-1, -1)

## The desk the screen is a view of.
var desk: Desk
## Seeds the page's sides, so that they are the same every time the page is opened.
var page_seed: int = 0
## The id the next parasitic fragment is given.
var next_parasite: int = FIRST_PARASITE_ID
## How many times this page was opened; reseeds the destruction rolls.
var opens: int = 0
## The fragment held, or null. The grid is visible exactly while this is not null.
var selected: Variant = null
## The fragment the cursor is on, or null.
var cursor: Variant = null


## What one request did, for the view to show and for [method report_to].
class Outcome:
	extends RefCounted
	## The desk's answer, or null when the request never reached it.
	var result: Results.MoveResult = null
	## No free tile for a fragment of the new fragment area to enter the desk on.
	var desk_full: bool = false
	## The fragment came from the new fragment area onto the desk.
	var entered: bool = false
	var snap: Results.SnapResult = null
	var destroyed: Array = []
	var parasites_removed: Array = []
	var parasites_cleared: Array = []
	var damaged: Array = []
	var completed: bool = false

	func accepted() -> bool:
		return result != null and result.accepted()

	## Why the desk refused, or NONE.
	func blocked() -> Results.MoveResult.Blocked:
		return result.blocked if result != null else Results.MoveResult.Blocked.NONE

	## Whether the snap, if any, was a HOLE: the player is told, as the doc suggests.
	func is_hole() -> bool:
		return snap != null and snap.reason == Results.SnapResult.Reason.HOLE

	func pushed_back() -> bool:
		return snap != null and snap.pushed_back


# --------------------------------------------------------------------------
# Building a desk
# --------------------------------------------------------------------------


## The seed of a page's sides, from what names the page. Fixed for good once saved.
static func seed_for(species_id: StringName, forlorn: bool) -> int:
	return ("%s/%s" % [species_id, "forlorn" if forlorn else "main"]).hash()


## The page cell of correct fragment `id`.
static func cell_of(id: int) -> Vector2i:
	return Vector2i(id % PAGE_COLS, id / PAGE_COLS)


## Opens a page: the saved layout if there is a sound one, otherwise a fresh desk. `true_count`,
## `parasite_count` and `arranged` are what the model says; `assembled` is a page at 100 %.
## A saved layout is dropped, and the page starts afresh, when it holds more fragments than the
## model says, or fewer arranged ones; fragments the model has and it lacks are added to the new
## fragment area.
static func open(
	species_id: StringName,
	forlorn: bool,
	state: Dictionary,
	true_count: int,
	parasite_count: int,
	arranged: int,
	assembled: bool
) -> Variant:
	var logic: Variant = new()
	logic.page_seed = int(state.get("seed", seed_for(species_id, forlorn)))
	logic.opens = int(state.get("opens", 0)) + 1
	logic._make_desk()
	if assembled:
		logic._build_assembled()
		return logic
	if not logic._restore(state, true_count, parasite_count, arranged):
		logic._make_desk()
		logic.next_parasite = FIRST_PARASITE_ID
		logic._build_fresh(true_count, parasite_count, arranged)
	return logic


func _make_desk() -> void:
	desk = Desk.new(DESK_TILES, FRAGMENT_TILES, hash([page_seed, opens]))


func _page_edges() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = page_seed
	return Edges.generate(PAGE_COLS, PAGE_ROWS, rng)


func _add_correct(id: int, edges: Dictionary) -> void:
	desk.add_correct(id, cell_of(id), edges[cell_of(id)])


func _add_parasite() -> int:
	var id := next_parasite
	next_parasite += 1
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([page_seed, id])
	desk.add_parasite(id, Edges.random_edges(rng))
	return id


## All fragments in the new fragment area, except the first `arranged` ones, which start already
## assembled in a block lying on its side: the starting duo's fragments are "correctly arranged"
## from the first day.
func _build_fresh(true_count: int, parasite_count: int, arranged: int) -> void:
	var edges := _page_edges()
	var count := clampi(true_count, 0, PAGE_FRAGMENTS)
	for id in PAGE_FRAGMENTS:
		if id < count:
			_add_correct(id, edges)
		else:
			desk.know_correct(id)
	var block := mini(arranged, count)
	if block > 1:
		_lay_block(block, Vector2i(1, 1))
	for i in parasite_count:
		_add_parasite()


## Puts correct fragments 0 .. count - 1 on the desk, in page order, turned a quarter, bonded to
## their neighbours, with the top-left tile of the block at `origin`.
func _lay_block(count: int, origin: Vector2i) -> void:
	var rows := ceili(float(count) / PAGE_COLS)
	for id in count:
		var cell := cell_of(id)
		var tile := origin + Vector2i((rows - 1 - cell.y) * FRAGMENT_TILES, cell.x * FRAGMENT_TILES)
		desk.restore_fragment(id, Fragment.Area.DESK, tile, 1, false, 0.0)
	for id in count:
		var cell := cell_of(id)
		for step in [Vector2i(1, 0), Vector2i(0, 1)]:
			var other: int = (cell.y + step.y) * PAGE_COLS + cell.x + step.x
			if cell.x + step.x < PAGE_COLS and other < count:
				desk.restore_bond(id, other)


## A finished page: all 33 fragments bonded, lying on its side, centred on the desk.
func _build_assembled() -> void:
	var edges := _page_edges()
	for id in PAGE_FRAGMENTS:
		_add_correct(id, edges)
	var size := Vector2i(PAGE_ROWS, PAGE_COLS) * FRAGMENT_TILES
	_lay_block(PAGE_FRAGMENTS, (DESK_TILES - size) / 2)
	desk.complete = true


# --------------------------------------------------------------------------
# Saving
# --------------------------------------------------------------------------


## The layout, JSON-safe, for a page's `puzzle_state`. Sides are not in it: they come from
## the seed.
func save_state() -> Dictionary:
	var fragments := []
	for id in desk.ids():
		var f: Fragment = desk.fragment(id)
		(
			fragments
			. append(
				{
					"id": id,
					"area": int(f.area),
					"x": f.position.x,
					"y": f.position.y,
					"rot": f.rotation,
					"damaged": f.damaged,
					"stain": f.stain,
				}
			)
		)
	return {
		"version": STATE_VERSION,
		"seed": page_seed,
		"opens": opens,
		"next_parasite": next_parasite,
		"complete": desk.complete,
		"fragments": fragments,
		"bonds": desk.bond_pairs(),
	}


## Puts a saved layout back, and brings it in line with the model. False if there is nothing
## sound to restore, in which case the desk is to be rebuilt.
func _restore(state: Dictionary, true_count: int, parasite_count: int, arranged: int) -> bool:
	if int(state.get("version", 0)) != STATE_VERSION or not state.get("fragments") is Array:
		return false
	var edges := _page_edges()
	next_parasite = maxi(int(state.get("next_parasite", FIRST_PARASITE_ID)), FIRST_PARASITE_ID)
	var correct := 0
	var parasites := 0
	for entry in state["fragments"]:
		if not entry is Dictionary or not entry.has("id"):
			return false
		var id := int(entry["id"])
		if desk.has_fragment(id):
			return false
		if id >= FIRST_PARASITE_ID:
			var rng := RandomNumberGenerator.new()
			rng.seed = hash([page_seed, id])
			desk.add_parasite(id, Edges.random_edges(rng))
			parasites += 1
		elif id >= 0 and id < PAGE_FRAGMENTS:
			_add_correct(id, edges)
			correct += 1
		else:
			return false
		var area := Fragment.Area.DESK if int(entry.get("area", 0)) == 1 else Fragment.Area.NEW
		desk.restore_fragment(
			id,
			area,
			Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0))),
			int(entry.get("rot", 0)),
			bool(entry.get("damaged", false)),
			float(entry.get("stain", 0.0))
		)
	for pair in state.get("bonds", []):
		if pair is Array and pair.size() == 2:
			desk.restore_bond(int(pair[0]), int(pair[1]))
	desk.complete = bool(state.get("complete", false)) and correct == PAGE_FRAGMENTS
	if correct > true_count or parasites > parasite_count:
		return false
	if desk.arranged_count() < arranged:
		return false
	for id in PAGE_FRAGMENTS:
		if not desk.has_fragment(id):
			desk.know_correct(id)
	# IFP gained since the page was last open: new fragments, in the new fragment area.
	return _add_missing(true_count, parasite_count)


## Gives the desk the fragments the model counts and it lacks: the lowest free page cells for
## correct ones. False if there are more than the model counts.
func _add_missing(true_count: int, parasite_count: int) -> bool:
	var edges := _page_edges()
	var correct := 0
	var parasites := 0
	for id in desk.ids():
		if int(id) >= FIRST_PARASITE_ID:
			parasites += 1
		else:
			correct += 1
	if correct > true_count or parasites > parasite_count:
		return false
	var id := 0
	while correct < true_count and id < PAGE_FRAGMENTS:
		if not desk.has_fragment(id):
			_add_correct(id, edges)
			correct += 1
		id += 1
	while parasites < parasite_count:
		_add_parasite()
		parasites += 1
	return true


## Brings the desk up to what the model counts, while the screen is open (IFP gained meanwhile).
## Returns the ids that appeared.
func add_new_fragments(true_count: int, parasite_count: int) -> Array:
	var before := desk.ids()
	_add_missing(true_count, parasite_count)
	var added := []
	for id in desk.ids():
		if not before.has(id):
			added.append(id)
	return added


# --------------------------------------------------------------------------
# Selecting and moving
# --------------------------------------------------------------------------


func is_selected() -> bool:
	return selected != null


## The grid shows only while a fragment is held.
func grid_visible() -> bool:
	return selected != null


## Holds `id`, in either area. False if there is no such fragment.
func select(id: Variant) -> bool:
	if id == null or not desk.has_fragment(id):
		return false
	selected = id
	cursor = id
	return true


func release() -> void:
	selected = null


## One tile in `direction` for the held fragment. A fragment of the new fragment area first
## enters the desk, at [method entry_tile], and that is its move.
func step(direction: Vector2i) -> Outcome:
	var outcome := Outcome.new()
	if selected == null:
		return outcome
	if desk.fragment(selected).area == Fragment.Area.NEW:
		var tile := entry_tile()
		if tile == NO_TILE:
			outcome.desk_full = true
			return outcome
		outcome.entered = true
		outcome.result = desk.place(selected, tile)
	else:
		outcome.result = desk.move(selected, direction)
	return _finish(outcome)


## A quarter turn for the held fragment (a lone one in the new fragment area simply turns).
func turn(clockwise: bool) -> Outcome:
	var outcome := Outcome.new()
	if selected == null:
		return outcome
	outcome.result = desk.rotate_fragment(selected, clockwise)
	return _finish(outcome)


## Sends the held fragment back to the new fragment area, if it is alone. True if it did.
func stash() -> bool:
	if selected == null or not desk.return_to_new_area(selected):
		return false
	selected = null
	return true


## Time spent handling: the held fragment's stain spreads.
func handle(seconds: float) -> void:
	if selected != null:
		desk.tick_handling(selected, seconds)


func _finish(outcome: Outcome) -> Outcome:
	if outcome.result.snaps.size() > 0:
		var snap: Results.SnapResult = outcome.result.snaps[0]
		outcome.snap = snap
		outcome.destroyed = snap.destroyed
		outcome.parasites_removed = snap.parasites_removed
		outcome.parasites_cleared = snap.parasites_cleared
		outcome.damaged = snap.damaged
		outcome.completed = snap.completed
	if selected != null and not desk.has_fragment(selected):
		selected = null
	if cursor != null and not desk.has_fragment(cursor):
		cursor = null
	return outcome


## Where a fragment of the new fragment area enters the desk: the free spot nearest the middle
## of the desk, preferring one far enough from every other fragment that nothing snaps on
## arrival. NO_TILE if the desk has no room at all.
func entry_tile() -> Vector2i:
	var rects: Array[Rect2i] = []
	for id in desk.ids():
		if desk.fragment(id).area == Fragment.Area.DESK:
			rects.append(desk.rect_of(id))
	for margin in [Desk.SNAP_DISTANCE, 0]:
		var best := NO_TILE
		var best_key := Vector2i.ZERO
		for y in range(0, DESK_TILES.y - FRAGMENT_TILES + 1):
			for x in range(0, DESK_TILES.x - FRAGMENT_TILES + 1):
				var rect := Rect2i(x, y, FRAGMENT_TILES, FRAGMENT_TILES).grow(margin)
				if _hits_any(rect, rects):
					continue
				# Squared distance between the rect's centre and the desk's, in half tiles.
				var dx := 2 * x + FRAGMENT_TILES - DESK_TILES.x
				var dy := 2 * y + FRAGMENT_TILES - DESK_TILES.y
				var key := Vector2i(dx * dx + dy * dy, y)
				if (
					best == NO_TILE
					or key.x < best_key.x
					or (key.x == best_key.x and key.y < best_key.y)
				):
					best = Vector2i(x, y)
					best_key = key
		if best != NO_TILE:
			return best
	return NO_TILE


static func _hits_any(rect: Rect2i, rects: Array[Rect2i]) -> bool:
	for other in rects:
		if rect.intersects(other):
			return true
	return false


# --------------------------------------------------------------------------
# The cursor
# --------------------------------------------------------------------------


## Fragments of the new fragment area, in the order they lie there: a fixed shuffle (the doc has
## them "in no particular order"), so that a fragment keeps its place while others come and go.
func new_area_order() -> Array:
	var ids := []
	for id in desk.ids():
		if desk.fragment(id).area == Fragment.Area.NEW:
			ids.append(id)
	var keyed := []
	for id in ids:
		keyed.append([hash([page_seed, id]), id])
	keyed.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var ordered := []
	for pair in keyed:
		ordered.append(pair[1])
	return ordered


## Every fragment in cycling order: those on the desk, top to bottom then left to right, then
## those of the new fragment area.
func cycle_order() -> Array:
	var on_desk := []
	for id in desk.ids():
		if desk.fragment(id).area == Fragment.Area.DESK:
			on_desk.append(id)
	on_desk.sort_custom(
		func(a: Variant, b: Variant) -> bool:
			var pa: Vector2i = desk.fragment(a).position
			var pb: Vector2i = desk.fragment(b).position
			return pa.y < pb.y or (pa.y == pb.y and pa.x < pb.x)
	)
	return on_desk + new_area_order()


## Puts the cursor somewhere sensible if it is nowhere: the first fragment in cycling order.
func ensure_cursor() -> void:
	if cursor != null and desk.has_fragment(cursor):
		return
	var order := cycle_order()
	cursor = order[0] if not order.is_empty() else null


## Moves the cursor to the next (`step` 1) or previous (-1) fragment in cycling order.
func cycle_cursor(step: int) -> void:
	var order := cycle_order()
	if order.is_empty():
		cursor = null
		return
	var at := order.find(cursor)
	cursor = order[posmod(at + step, order.size())] if at >= 0 else order[0]


## Moves the cursor to the fragment lying in `direction` from it. `centres` maps every
## fragment's id to the pixel position of its centre, in either area.
func hop_cursor(centres: Dictionary, direction: Vector2) -> void:
	ensure_cursor()
	if cursor == null:
		return
	var target: Variant = hop_target(centres, cursor, direction)
	if target != null:
		cursor = target


## The fragment to hop to from `from` in `direction` (a unit axis vector): the one ahead that is
## nearest, counting a sideways offset double. With none ahead the hop wraps, as the encyclopaedia
## grid does, to the farthest one behind, the best aligned. Null if `from` is alone.
static func hop_target(centres: Dictionary, from: Variant, direction: Vector2) -> Variant:
	if not centres.has(from):
		return null
	var origin: Vector2 = centres[from]
	var ahead: Variant = null
	var ahead_score := INF
	var behind: Variant = null
	var behind_score := INF
	for id in centres:
		if id == from:
			continue
		var delta: Vector2 = centres[id] - origin
		var along := delta.dot(direction)
		var across := absf(delta.cross(direction))
		if along > 0.5:
			var score := along + 2.0 * across
			if score < ahead_score:
				ahead = id
				ahead_score = score
		else:
			# Behind, `along` is negative: the farthest comes first, so that a hop off one
			# end lands on the other.
			var score := along + 2.0 * across
			if score < behind_score:
				behind = id
				behind_score = score
	return ahead if ahead != null else behind


# --------------------------------------------------------------------------
# Reporting to the session
# --------------------------------------------------------------------------


## Tells the session what the request did, in the order its model needs: destroyed fragments,
## vanished parasites, how many fragments are correctly arranged now, and, if the page was
## completed, that it is. `session` is [GameSession], or anything with the same four methods.
func report_to(
	session: Object, species_id: StringName, forlorn: bool, outcome: Outcome = null
) -> void:
	if outcome != null:
		if outcome.destroyed.size() > 0:
			session.destroy_fragments(species_id, forlorn, outcome.destroyed.size())
		var vanished := outcome.parasites_removed.size() + outcome.parasites_cleared.size()
		if vanished > 0:
			session.remove_parasitic_fragments(species_id, forlorn, vanished)
	session.set_arranged_fragments(species_id, forlorn, desk.arranged_count())
	if outcome != null and outcome.completed:
		session.mark_page_assembled(species_id, forlorn)


# --------------------------------------------------------------------------
# Tiles and pixels
# --------------------------------------------------------------------------


## The pixel size of a tile that makes the desk fit `area` whole.
static func tile_px_for(area: Vector2) -> float:
	return minf(area.x / DESK_TILES.x, area.y / DESK_TILES.y)


## Where the desk lies in `area`: as big as fits, centred.
static func desk_rect(area: Rect2) -> Rect2:
	var px := tile_px_for(area.size)
	var size := Vector2(DESK_TILES) * px
	return Rect2(area.position + (area.size - size) / 2.0, size)


static func tile_to_px(tile: Vector2i, tile_px: float, origin: Vector2) -> Vector2:
	return origin + Vector2(tile) * tile_px


## The tile a pixel falls in, rounded to the nearest corner (a fragment's top-left).
static func px_to_tile(pixel: Vector2, tile_px: float, origin: Vector2) -> Vector2i:
	return Vector2i(((pixel - origin) / tile_px).round())


## How the new fragment area lays out `count` fragments in `area`: the biggest square slot, up to
## `max_slot`, with which they all fit in rows and columns. {slot, cols, rows}; slot 0 if even
## the smallest does not fit.
static func slot_layout(
	area: Vector2, count: int, max_slot: float, gap: float = 14.0
) -> Dictionary:
	var slot := max_slot
	while slot >= 16.0:
		var cols := int((area.x + gap) / (slot + gap))
		var rows := int((area.y + gap) / (slot + gap))
		if cols > 0 and rows > 0 and cols * rows >= count:
			return {"slot": slot, "cols": cols, "rows": rows}
		slot -= 2.0
	return {"slot": 0.0, "cols": 1, "rows": 1}


## Top-left of slot `index` (row by row), the grid of slots centred across `area`.
static func slot_position(
	index: int, layout: Dictionary, area: Rect2, gap: float = 14.0
) -> Vector2:
	var cols: int = layout["cols"]
	var slot: float = layout["slot"]
	var width := cols * slot + (cols - 1) * gap
	var left := area.position.x + (area.size.x - width) / 2.0
	return Vector2(
		left + (index % cols) * (slot + gap), area.position.y + (index / cols) * (slot + gap)
	)
