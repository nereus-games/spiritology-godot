## One fragment on the assembly desk: what it is, where it lies, what has happened to it.
##
## Plain data, owned by the desk (puzzle_desk.gd); nothing here moves itself. `id` is opaque: the
## desk never looks inside it, so whatever the page model uses to name a fragment can be used.
extends RefCounted

## Where the fragment lies. NEW is the new fragment area, where fragments are inert and stick to
## nothing; DESK is the manipulation area, where `position` is meaningful.
enum Area { NEW, DESK }

## Not a cell of any page: a parasitic fragment.
const NO_CELL := Vector2i(-1, -1)

var id: Variant
## Where this fragment belongs on its page, in fragments (not tiles). NO_CELL for a parasite,
## which belongs nowhere.
var page_cell: Vector2i = NO_CELL
## The sides as drawn on the page, see puzzle_edges.gd.
var edges := PackedInt32Array([0, 0, 0, 0])
var area: Area = Area.NEW
## Top-left tile on the desk. Meaningless while the fragment is in the new fragment area.
var position := Vector2i.ZERO
## Quarter-turns clockwise, 0..3. Page orientation is 0.
var rotation: int = 0
var damaged: bool = false
## How much of the fragment the black stain covers, from 0 to the balance cap.
var stain: float = 0.0


func is_parasitic() -> bool:
	return page_cell == NO_CELL
