## What the assembly desk reports back, as small data objects. No signals: the desk is logic
## only, and the caller (a view) reads the result of each call and decides what to show or play.
extends RefCounted


## The outcome of one automatic snap.
class SnapResult:
	extends RefCounted

	## Why a snap succeeded or failed. HOLE is the one the doc suggests telling the player
	## about ("some could be confused and keep trying"): the two fragments are right for each
	## other, and something else stands in the way.
	enum Reason { OK, PARASITIC, MISMATCH, HOLE }

	var reason: Reason = Reason.OK
	## The two fragments that met. `mover` is the one the player was moving (it is also `a`
	## or `b`).
	var a: Variant
	var b: Variant
	var mover: Variant
	## Parasites that disappeared, with the snickering sound.
	var parasites_removed: Array = []
	## Parasites that disappeared because the page was completed: silently, this time.
	var parasites_cleared: Array = []
	## Correct fragments that became damaged.
	var damaged: Array = []
	## Correct fragments that were destroyed, their information points to be obtained again.
	var destroyed: Array = []
	## Whether the moved fragments were pushed back to where they stood (or to the new fragment
	## area, if they came from there).
	var pushed_back: bool = false
	## Whether this snap completed the page.
	var completed: bool = false

	func is_correct() -> bool:
		return reason == Reason.OK


## The outcome of a move, a rotation or a placement.
class MoveResult:
	extends RefCounted

	## Why a request was refused. The desk is left untouched in every case but NONE.
	enum Blocked { NONE, UNKNOWN_FRAGMENT, NOT_ON_DESK, BAD_DIRECTION, OUT_OF_AREA, OVERLAP }

	var blocked: Blocked = Blocked.NONE
	## Snaps this request set off: none or one.
	var snaps: Array[SnapResult] = []

	## Whether the request was carried out. A move that set off an incorrect snap WAS carried
	## out, then undone: see `SnapResult.pushed_back`.
	func accepted() -> bool:
		return blocked == Blocked.NONE
