## The encyclopaedia grid's rules, with no node in sight, so that a headless check can drive them.
##
## Design doc, Encyclopaedia: the grid is rectangular, leaving it by one side lands on the
## opposite side, the selector never rests on an undiscovered species — it goes to the closest
## discovered one, and "if there are 2 closest discovered species, the selector defaults to the
## down/right direction" — and an icon changes with the page's IFP.
##
## Cells are addressed by their index in the species list, laid out row by row. `discovered` is
## an array of booleans, one per cell, so this script knows nothing of [GameSession].
##
## No `class_name` (the CLI class-cache trap): referenced by `preload`.
extends RefCounted

## What an icon looks like. Source: design doc, Encyclopaedia / Page Contents / Icon.
enum IconState {
	NONE,  ## 0 IFP: no icon
	BLACK,  ## 1 to 44 IFP: a plain black icon
	GRAY,  ## 45 to 99 IFP: a grayscale icon
	COLOUR,  ## 99 IFP and the correct assembly: full colour
}

const BLACK_FROM := 1
const GRAY_FROM := 45
## IFP caps at 99 until the page is correctly assembled, whose last percent reads 100.
const COMPLETE := 100


## The icon for a page at `ifp` points. 99 IFP stays grayscale: colour needs the assembly, which
## reads 100.
##
## SEAM: today [method GameSession.add_ifp] caps at 100 with no assembly behind it, so 100 here
## only means "the number says so". Once the fragment model lands, the page being assembled is
## the condition, and this is the one function to change.
static func icon_state(ifp: int) -> IconState:
	if ifp >= COMPLETE:
		return IconState.COLOUR
	if ifp >= GRAY_FROM:
		return IconState.GRAY
	if ifp >= BLACK_FROM:
		return IconState.BLACK
	return IconState.NONE


## Oddity "swapped_icons": the cell whose icon is shown in cell `index`, its neighbour in the pair
## (0 and 1, 2 and 3, ...). A last cell with no partner keeps its own.
static func swapped_icon_cell(index: int, count: int) -> int:
	var partner := index ^ 1
	return partner if partner < count else index


## The number of columns for `count` cells: as square as it gets.
static func columns_for(count: int) -> int:
	return maxi(1, ceili(sqrt(float(count))))


## Where the selector would land after one step in `dir`, ignoring discovery: leaving a row or a
## column by one end comes back by the other. A last row that is not full wraps within its own
## cells, and so does a column that is one cell shorter than the others. `from` is an index.
static func wrapped_step(columns: int, count: int, from: int, dir: Vector2i) -> int:
	if count <= 0:
		return -1
	var col := from % columns
	var row := from / columns
	if dir.x != 0:
		var row_len := mini(columns, count - row * columns)
		col = posmod(col + dir.x, row_len)
	if dir.y != 0:
		var col_len := ceili(float(count - col) / columns)
		row = posmod(row + dir.y, col_len)
	return row * columns + col


## The discovered cell closest to cell `target` — straight-line distance between tile centres —
## or -1 if nothing is discovered. Of two equally close cells the lower one wins, and of two on
## the same row the right one: the doc's "down/right". `exclude` is left out unless it is the
## only discovered cell, so that a selector pushed against an undiscovered area moves on instead
## of standing still when a cell further along exists.
static func nearest_discovered(
	columns: int, discovered: Array, target: int, exclude: int = -1
) -> int:
	var best := -1
	var best_key := Vector3i.ZERO
	var tc := target % columns
	var tr := target / columns
	for i in discovered.size():
		if not discovered[i] or i == exclude:
			continue
		var dc: int = i % columns - tc
		var dr: int = i / columns - tr
		# Smaller distance first, then the lower row, then the right column: negated, so that
		# "smaller key wins" holds for every part.
		var key := Vector3i(dc * dc + dr * dr, -dr, -dc)
		if best == -1 or _key_less(key, best_key):
			best = i
			best_key = key
	if best == -1 and exclude >= 0 and exclude < discovered.size() and discovered[exclude]:
		return exclude
	return best


## One step of the selector. Returns the new cell, which is `from` when there is nowhere to go.
static func move(columns: int, discovered: Array, from: int, dir: Vector2i) -> int:
	var landing := wrapped_step(columns, discovered.size(), from, dir)
	if landing < 0:
		return from
	if discovered[landing]:
		return landing
	var near := nearest_discovered(columns, discovered, landing, from)
	return from if near < 0 else near


## Where the selector starts: the last examined species when it is discovered, otherwise the
## discovered cell closest to it (or to the first cell when none is given). -1 for an empty
## encyclopaedia.
static func start_index(columns: int, discovered: Array, preferred: int) -> int:
	if preferred >= 0 and preferred < discovered.size() and discovered[preferred]:
		return preferred
	return nearest_discovered(columns, discovered, maxi(preferred, 0))


static func _key_less(a: Vector3i, b: Vector3i) -> bool:
	if a.x != b.x:
		return a.x < b.x
	if a.y != b.y:
		return a.y < b.y
	return a.z < b.z
