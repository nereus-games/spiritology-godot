## Headless check on the assembly desk's logic (scripts/encyclopaedia/puzzle_*.gd), against the
## design doc ("Page Assembly / Fragment Manipulation"): no overlap, the snap distance, the three
## ways a snap goes wrong and what each costs, destruction, rotation, groups, stain, completion.
##
## Run with: Godot --headless --path . res://scenes/dev/puzzle_check.tscn
## As a start scene rather than --script; see geometry_check.gd.
extends Node

const Desk := preload("res://scripts/encyclopaedia/puzzle_desk.gd")
const Edges := preload("res://scripts/encyclopaedia/puzzle_edges.gd")
const Fragment := preload("res://scripts/encyclopaedia/puzzle_fragment.gd")
const Results := preload("res://scripts/encyclopaedia/puzzle_results.gd")

const OK := Results.SnapResult.Reason.OK
const PARASITIC := Results.SnapResult.Reason.PARASITIC
const MISMATCH := Results.SnapResult.Reason.MISMATCH
const HOLE := Results.SnapResult.Reason.HOLE
const BLOCKED := Results.MoveResult.Blocked

var _fails: Array[String] = []


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  OK   %s" % label)
	else:
		print("  FAIL %s" % label)
		_fails.append(label)


func _ready() -> void:
	_run_all()


func _run_all() -> void:
	await get_tree().process_frame
	_check_edges()
	_check_overlap_and_bounds()
	_check_snap_distance()
	_check_parasitic()
	_check_mismatch()
	_check_hole_blocked()
	_check_hole_cavity_and_completion()
	_check_destruction()
	_check_rotation()
	_check_rotated_snap()
	_check_group_move()
	_check_stain()
	_check_generated_page()
	print("")
	if _fails.is_empty():
		print("ALL OK")
	else:
		print("FAILURES: %s" % [_fails])
	get_tree().quit(0 if _fails.is_empty() else 1)


# --------------------------------------------------------------------------
# Fixtures
# --------------------------------------------------------------------------


## A desk whose destruction chance is `destroy_chance`, so that no check depends on a roll.
func _desk(destroy_chance: float = 0.25) -> Desk:
	var desk := Desk.new(Vector2i(24, 16), 4, 7)
	desk.balance = BalanceData.current().duplicate() as BalanceData
	desk.balance.puzzle_destroy_chance = destroy_chance
	return desk


## A two-fragment page: A (id 0) left of B (id 1). A's east side, 7, fits B's west side, 56.
func _pair(destroy_chance: float = 0.25) -> Desk:
	var desk := _desk(destroy_chance)
	desk.add_correct(0, Vector2i(0, 0), PackedInt32Array([1, 7, 2, 3]))
	desk.add_correct(1, Vector2i(1, 0), PackedInt32Array([4, 9, 5, 56]))
	return desk


## The pair, on a page that has a third fragment (id 2) left in the new area, so that bonding the
## two does not complete the page and sweep the parasites away.
func _trio() -> Desk:
	var desk := _pair()
	desk.add_correct(2, Vector2i(2, 0), PackedInt32Array([8, 10, 12, 20]))
	return desk


func _move_n(desk: Desk, id: int, dir: Vector2i, times: int) -> Results.MoveResult:
	var last: Results.MoveResult = null
	for _i in times:
		last = desk.move(id, dir)
	return last


func _pos(desk: Desk, id: int) -> Vector2i:
	return desk.fragment(id).position


func _first_snap(r: Results.MoveResult) -> Results.SnapResult:
	return r.snaps[0] if not r.snaps.is_empty() else null


# --------------------------------------------------------------------------
# The edge model
# --------------------------------------------------------------------------


func _check_edges() -> void:
	print("— edges —")
	_check(Edges.compatible(7, 56), "a side fits its negative")
	_check(not Edges.compatible(7, 55), "a side does not fit a near miss")
	_check(not Edges.compatible(7, 7), "a side does not fit itself")
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var page := Edges.generate(3, 3, rng)
	var every_pair_fits := true
	var flat_sides := false
	for cell in page:
		for side in [Edges.NORTH, Edges.EAST, Edges.SOUTH, Edges.WEST]:
			if page[cell][side] <= 0 or page[cell][side] >= Edges.FULL:
				flat_sides = true
			var next: Vector2i = cell + Edges.STEP[side]
			if page.has(next):
				every_pair_fits = (
					every_pair_fits
					and Edges.compatible(page[cell][side], page[next][Edges.opposite(side)])
				)
	_check(every_pair_fits, "neighbours on a generated page have complementary sides")
	_check(not flat_sides, "no generated side is flat")
	rng.seed = 11
	_check(Edges.generate(3, 3, rng) == page, "the same seed draws the same sides")
	rng.seed = 12
	_check(Edges.generate(3, 3, rng) != page, "another seed draws other sides")
	# Turning both fragments of a neighbouring pair together keeps their sides fitting.
	var turned_fits := true
	for rotation in 4:
		for cell in page:
			var right: Vector2i = cell + Vector2i.RIGHT
			if not page.has(right):
				continue
			var physical: int = (Edges.EAST + rotation) % 4
			var mine := Edges.side_signature(page[cell], rotation, physical)
			var theirs := Edges.side_signature(page[right], rotation, Edges.opposite(physical))
			turned_fits = turned_fits and Edges.compatible(mine, theirs)
	_check(turned_fits, "turned together, neighbours still fit, at every rotation")


# --------------------------------------------------------------------------
# No overlap, no leaving the desk
# --------------------------------------------------------------------------


func _check_overlap_and_bounds() -> void:
	print("— overlap and bounds —")
	var desk := _desk()
	desk.add_parasite(10, PackedInt32Array([1, 1, 1, 1]))
	desk.add_parasite(11, PackedInt32Array([1, 1, 1, 1]))
	_check(desk.place(10, Vector2i(4, 4)).accepted(), "a fragment is placed on the desk")
	var r := desk.place(11, Vector2i(6, 6))
	_check(r.blocked == BLOCKED.OVERLAP, "placing over another fragment is refused")
	_check(
		desk.fragment(11).area == Fragment.Area.NEW, "the refused fragment stays in the new area"
	)
	r = desk.place(11, Vector2i(8, 4))
	_check(r.accepted() and r.snaps.is_empty(), "placing right beside it is fine and snaps nothing")
	# Edges touch at x = 8: 11 may not move left, onto 10.
	r = desk.move(11, Vector2i.LEFT)
	_check(r.blocked == BLOCKED.OVERLAP, "a move onto another fragment is refused")
	_check(_pos(desk, 11) == Vector2i(8, 4), "a refused move changes nothing")
	r = desk.move(11, Vector2i.DOWN)
	_check(r.accepted() and _pos(desk, 11) == Vector2i(8, 5), "a sliding move beside it is fine")
	_check(
		desk.place(11, Vector2i(0, 0)).blocked == BLOCKED.NOT_ON_DESK, "place needs the new area"
	)
	var corner := _desk()
	corner.add_parasite(1, PackedInt32Array([1, 1, 1, 1]))
	_check(
		corner.place(1, Vector2i(21, 0)).blocked == BLOCKED.OUT_OF_AREA,
		"a fragment cannot stick out of the desk"
	)
	_check(corner.place(1, Vector2i(20, 12)).accepted(), "the last tile of the desk is usable")
	_check(corner.move(1, Vector2i.RIGHT).blocked == BLOCKED.OUT_OF_AREA, "no move off the desk")
	_check(corner.move(1, Vector2i(1, 1)).blocked == BLOCKED.BAD_DIRECTION, "no diagonal moves")
	_check(corner.move(1, Vector2i.ZERO).blocked == BLOCKED.BAD_DIRECTION, "no zero moves")
	_check(
		corner.move(99, Vector2i.UP).blocked == BLOCKED.UNKNOWN_FRAGMENT, "an unknown id is refused"
	)
	var fresh := _desk()
	fresh.add_parasite(1, PackedInt32Array([1, 1, 1, 1]))
	_check(fresh.move(1, Vector2i.UP).blocked == BLOCKED.NOT_ON_DESK, "no moving in the new area")
	_check(
		_desk(0.25).fragment_size == 4 and Desk.new(Vector2i(8, 8), 2).fragment_size == 4,
		"a fragment is never smaller than 4 x 4 tiles"
	)


# --------------------------------------------------------------------------
# The snap distance
# --------------------------------------------------------------------------


func _check_snap_distance() -> void:
	print("— snap distance —")
	var desk := _pair()
	desk.place(0, Vector2i(2, 2))
	_check(desk.place(1, Vector2i(9, 2)).snaps.is_empty(), "3 tiles apart: nothing happens")
	var r := desk.move(1, Vector2i.LEFT)
	_check(_pos(desk, 1) == Vector2i(8, 2), "moved to 2 tiles apart")
	_check(r.snaps.is_empty() and desk.group_of(0).size() == 1, "2 tiles apart: no snap")
	r = desk.move(1, Vector2i.LEFT)
	var snap := _first_snap(r)
	_check(snap != null and snap.reason == OK, "1 tile apart: the snap is correct")
	_check(_pos(desk, 1) == Vector2i(6, 2), "the snapped fragment lies flush against its neighbour")
	_check(desk.group_of(0) == [0, 1], "the two now form a group")
	_check(snap != null and snap.completed, "the pair is the whole page, so it is complete")
	_check(desk.complete and is_equal_approx(desk.completion(), 1.0), "completion reads 100 %")

	# Off alignment counts too: 2 tiles off does not snap, 1 does, and alignment is made.
	desk = _pair()
	desk.place(0, Vector2i(2, 2))
	desk.place(1, Vector2i(9, 4))
	r = _move_n(desk, 1, Vector2i.LEFT, 2)
	_check(r.snaps.is_empty(), "1 tile apart but 2 tiles out of line: no snap")
	r = desk.move(1, Vector2i.UP)
	_check(_first_snap(r) != null and _first_snap(r).reason == OK, "1 tile out of line: snaps")
	_check(_pos(desk, 1) == Vector2i(6, 2), "and is brought into line")

	# Touching already (0 tiles apart) snaps too, and from either side.
	desk = _pair()
	desk.place(1, Vector2i(10, 6))
	r = desk.place(0, Vector2i(6, 6))
	_check(_first_snap(r) != null and _first_snap(r).reason == OK, "placed flush against: snaps")
	desk = _pair()
	desk.place(1, Vector2i(10, 6))
	desk.place(0, Vector2i(3, 6))
	r = desk.move(0, Vector2i.RIGHT)
	_check(r.snaps.is_empty(), "2 tiles apart the other way round: no snap")
	r = desk.move(0, Vector2i.RIGHT)
	_check(_first_snap(r) != null and _first_snap(r).reason == OK, "1 tile apart: snaps")
	_check(_pos(desk, 0) == Vector2i(6, 6), "the moving one is the one that lands flush")

	# Sides that do not fit do not snap at all, however close.
	desk = _desk()
	desk.add_correct(0, Vector2i(0, 0), PackedInt32Array([1, 7, 2, 3]))
	desk.add_correct(1, Vector2i(1, 0), PackedInt32Array([4, 9, 5, 6]))
	desk.place(0, Vector2i(2, 2))
	r = desk.place(1, Vector2i(6, 2))
	_check(r.snaps.is_empty() and desk.group_of(0).size() == 1, "sides that do not fit: no snap")

	# The new area is inert.
	desk = _pair()
	desk.place(0, Vector2i(2, 2))
	_check(
		desk.group_of(1) == [1] and desk.fragment(1).area == Fragment.Area.NEW, "new area is inert"
	)


# --------------------------------------------------------------------------
# The three incorrect snaps
# --------------------------------------------------------------------------


func _check_parasitic() -> void:
	print("— parasitic —")
	# The parasite is the one being moved.
	var desk := _desk(1.0)
	desk.add_correct(0, Vector2i(0, 0), PackedInt32Array([1, 7, 2, 3]))
	desk.add_parasite(5, PackedInt32Array([16, 17, 18, 56]))
	desk.place(0, Vector2i(2, 2))
	desk.place(5, Vector2i(9, 2))
	var r := _move_n(desk, 5, Vector2i.LEFT, 2)
	var snap := _first_snap(r)
	_check(snap != null and snap.reason == PARASITIC, "a parasite that fits is reported PARASITIC")
	_check(snap != null and snap.parasites_removed == [5], "the parasite disappears")
	_check(not desk.has_fragment(5), "and is gone from the desk")
	_check(desk.fragment(0).damaged and snap.damaged == [0], "the correct fragment is damaged")
	_check(desk.has_fragment(0), "a first offence destroys nothing, even with a certain chance")
	_check(snap != null and not snap.pushed_back, "nothing left to push back")

	# The correct fragment is the one being moved, and is pushed back.
	desk = _desk()
	desk.add_correct(0, Vector2i(0, 0), PackedInt32Array([1, 7, 2, 3]))
	desk.add_parasite(5, PackedInt32Array([16, 17, 18, 56]))
	desk.place(5, Vector2i(10, 2))
	desk.place(0, Vector2i(3, 2))
	r = desk.move(0, Vector2i.RIGHT)
	_check(r.snaps.is_empty(), "2 tiles apart: the parasite is left alone")
	r = desk.move(0, Vector2i.RIGHT)
	snap = _first_snap(r)
	_check(
		snap != null and snap.reason == PARASITIC, "moving a fragment onto a parasite: PARASITIC"
	)
	_check(
		_pos(desk, 0) == Vector2i(4, 2) and snap.pushed_back, "the moved fragment is pushed back"
	)
	_check(not desk.has_fragment(5) and desk.fragment(0).damaged, "parasite gone, fragment damaged")

	# A parasite in the new area is not part of any of this; and a parasite never bonds.
	desk = _desk()
	desk.add_correct(0, Vector2i(0, 0), PackedInt32Array([1, 7, 2, 3]))
	desk.add_parasite(5, PackedInt32Array([16, 17, 18, 56]))
	desk.place(0, Vector2i(2, 2))
	_check(desk.has_fragment(5) and desk.group_of(5) == [5], "a parasite in the new area stays put")


func _check_mismatch() -> void:
	print("— mismatch —")
	var desk := _desk()
	desk.add_correct(0, Vector2i(0, 0), PackedInt32Array([1, 7, 2, 3]))
	desk.add_correct(1, Vector2i(1, 0), PackedInt32Array([4, 9, 5, 56]))
	# Fits A's east side, but belongs two cells away.
	desk.add_correct(2, Vector2i(2, 0), PackedInt32Array([8, 10, 12, 56]))
	desk.place(0, Vector2i(2, 2))
	desk.place(2, Vector2i(9, 2))
	var r := _move_n(desk, 2, Vector2i.LEFT, 2)
	var snap := _first_snap(r)
	_check(
		snap != null and snap.reason == MISMATCH, "correct fragments that do not match: MISMATCH"
	)
	_check(desk.fragment(0).damaged and desk.fragment(2).damaged, "both are damaged")
	_check(snap != null and snap.damaged == [2, 0] and snap.destroyed.is_empty(), "and reported")
	_check(_pos(desk, 2) == Vector2i(8, 2) and snap.pushed_back, "the moved one is pushed back")
	_check(desk.group_of(0) == [0], "nothing bonded")
	_check(desk.has_fragment(0) and desk.has_fragment(2), "neither is lost on a first offence")

	# Turned a half-turn, a fragment shows its base east side on the west, which does not fit.
	desk = _pair()
	desk.place(0, Vector2i(2, 2))
	desk.rotate_fragment(1)
	desk.rotate_fragment(1)
	var shown := Edges.side_signature(desk.fragment(1).edges, 2, Edges.WEST)
	_check(not Edges.compatible(7, shown), "a half-turned neighbour presents another profile")
	r = desk.place(1, Vector2i(6, 2))
	_check(r.snaps.is_empty(), "so it does not snap")


func _check_hole_blocked() -> void:
	print("— hole: blocked —")
	var desk := _pair()
	desk.add_correct(2, Vector2i(5, 5), PackedInt32Array([1, 1, 1, 1]))
	desk.place(1, Vector2i(10, 6))
	# A bystander on the tiles A would need to land on, though not on those it stands on.
	desk.place(2, Vector2i(6, 3))
	var r := desk.place(0, Vector2i(5, 7))
	var snap := _first_snap(r)
	_check(snap != null and snap.reason == HOLE, "right fragments, but no room to snap: HOLE")
	_check(snap != null and snap.damaged == [0, 1], "both correct fragments are damaged")
	_check(
		desk.fragment(0).area == Fragment.Area.NEW and snap.pushed_back,
		"pushed back to the new area"
	)
	_check(desk.group_of(1) == [1], "nothing bonded")
	_check(_pos(desk, 1) == Vector2i(10, 6) and _pos(desk, 2) == Vector2i(6, 3), "others stay put")


func _check_hole_cavity_and_completion() -> void:
	print("— hole: cavity, then completion —")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var page := Edges.generate(3, 3, rng)
	var desk := _desk()
	for y in 3:
		for x in 3:
			desk.add_correct(y * 3 + x, Vector2i(x, y), page[Vector2i(x, y)])
	desk.add_parasite(100, Edges.random_edges(rng))
	# The ring around the middle cell, in an order that closes it with fragment 3.
	var ring := [0, 1, 2, 5, 8, 7, 6]
	var all_ok := true
	for id in ring:
		var r := desk.place(id, Vector2i(2 + 4 * (id % 3), 2 + 4 * (id / 3)))
		all_ok = all_ok and desk.fragment(id).area == Fragment.Area.DESK
		if id != ring[0]:
			var s := _first_snap(r)
			all_ok = all_ok and s != null and s.reason == OK
	_check(all_ok, "a ring of seven fragments is assembled snap by snap")
	_check(desk.group_of(0).size() == 7, "in one group")
	var closing := desk.place(3, Vector2i(2, 6))
	var snap := _first_snap(closing)
	_check(snap != null and snap.reason == HOLE, "closing the ring around an empty cell: HOLE")
	_check(desk.fragment(3).area == Fragment.Area.NEW, "the closing fragment is pushed back")
	_check(desk.fragment(3).damaged and desk.fragment(0).damaged, "and damage is dealt")
	_check(not desk.complete, "the page is not complete")
	# Fill the middle first and the same fragment fits.
	desk.fragment(2).stain = 0.5
	var centre := desk.place(4, Vector2i(6, 6))
	_check(_first_snap(centre) != null and _first_snap(centre).reason == OK, "the middle one snaps")
	_check(not desk.complete, "eight of nine is not complete")
	_check(absf(desk.completion() - 8.0 / 9.0) < 0.001, "completion reads 8/9")
	closing = desk.place(3, Vector2i(2, 6))
	snap = _first_snap(closing)
	_check(snap != null and snap.reason == OK, "then the last one fits")
	_check(snap != null and snap.completed and desk.complete, "and completes the page")
	_check(
		snap != null and snap.parasites_cleared == [100], "the remaining parasite goes, silently"
	)
	_check(snap != null and snap.parasites_removed.is_empty(), "without the snickering")
	var repaired := true
	for id in desk.ids():
		repaired = repaired and not desk.fragment(id).damaged and desk.fragment(id).stain == 0.0
	_check(repaired, "damage and stain are repaired")
	_check(desk.group_of(0).size() == 9, "nine fragments in one group")


func _check_destruction() -> void:
	print("— destruction —")
	for certain in [true, false]:
		var desk := _desk(1.0 if certain else 0.0)
		desk.add_correct(0, Vector2i(0, 0), PackedInt32Array([1, 7, 2, 3]))
		desk.add_correct(1, Vector2i(1, 0), PackedInt32Array([4, 9, 5, 56]))
		desk.add_correct(2, Vector2i(2, 0), PackedInt32Array([8, 10, 12, 56]))
		desk.place(0, Vector2i(2, 2))
		desk.place(2, Vector2i(9, 2))
		var first := _first_snap(_move_n(desk, 2, Vector2i.LEFT, 2))
		_check(first != null and first.destroyed.is_empty(), "first offence: damaged only")
		var second := _first_snap(desk.move(2, Vector2i.LEFT))
		_check(second != null and second.reason == MISMATCH, "second attempt is a mismatch again")
		if certain:
			_check(second.destroyed == [2, 0], "already damaged, with a certain chance: destroyed")
			_check(not desk.has_fragment(0) and not desk.has_fragment(2), "gone from the desk")
			_check(not second.pushed_back, "nothing left to push back")
			_check(desk.completion() == 0.0, "completion does not count them")
			# Obtaining the IFP anew brings the fragment back, undamaged.
			desk.add_correct(0, Vector2i(0, 0), PackedInt32Array([1, 7, 2, 3]))
			_check(desk.has_fragment(0) and not desk.fragment(0).damaged, "re-obtained fresh")
		else:
			_check(second.destroyed.is_empty(), "already damaged, with no chance: it survives")
			_check(desk.fragment(0).damaged and desk.fragment(2).damaged, "and stays damaged")
	# A destroyed fragment leaves the rest of its group standing, and the bond goes with it.
	var desk := _pair(1.0)
	# Fits B's east side (set to 7 below) but belongs under A, not beside B.
	desk.add_correct(2, Vector2i(0, 1), PackedInt32Array([8, 10, 12, 56]))
	desk.place(0, Vector2i(2, 2))
	desk.place(1, Vector2i(6, 2))
	_check(desk.group_of(0) == [0, 1], "two bonded")
	_check(absf(desk.completion() - 2.0 / 3.0) < 0.001, "completion reads 2/3 on a page of three")
	desk.fragment(1).damaged = true
	desk.fragment(1).edges[Edges.EAST] = 7
	desk.place(2, Vector2i(13, 2))
	var hit := _first_snap(_move_n(desk, 2, Vector2i.LEFT, 2))
	_check(hit != null and hit.reason == MISMATCH, "the stray third fragment mismatches")
	_check(
		hit != null and hit.destroyed == [1] and hit.damaged == [2], "the damaged one is destroyed"
	)
	_check(
		desk.has_fragment(0) and not desk.has_fragment(1), "the other member of its group stands"
	)
	_check(desk.group_of(0) == [0], "and the bond is gone with it")
	_check(
		hit != null and hit.pushed_back and _pos(desk, 2) == Vector2i(12, 2),
		"the mover is pushed back"
	)


# --------------------------------------------------------------------------
# Rotation and groups
# --------------------------------------------------------------------------


func _check_rotation() -> void:
	print("— rotation —")
	var desk := _desk()
	desk.add_parasite(1, PackedInt32Array([1, 1, 1, 1]))
	_check(
		desk.rotate_fragment(1).accepted() and desk.fragment(1).rotation == 1,
		"turns in the new area"
	)
	desk.rotate_fragment(1, false)
	desk.rotate_fragment(1, false)
	_check(desk.fragment(1).rotation == 3, "either way, modulo four")
	desk.place(1, Vector2i(4, 4))
	desk.rotate_fragment(1)
	_check(
		desk.fragment(1).rotation == 0 and _pos(desk, 1) == Vector2i(4, 4), "turns where it stands"
	)

	# A bonded pair turns as one.
	desk = _pair()
	desk.place(0, Vector2i(2, 2))
	desk.place(1, Vector2i(6, 2))
	var r := desk.rotate_fragment(0)
	_check(r.accepted(), "a group turns")
	_check(
		_pos(desk, 0) == Vector2i(2, 2) and _pos(desk, 1) == Vector2i(2, 6),
		"clockwise: B ends below A"
	)
	_check(desk.fragment(0).rotation == 1 and desk.fragment(1).rotation == 1, "both turned")
	desk.rotate_fragment(1, false)
	_check(_pos(desk, 0) == Vector2i(2, 2) and _pos(desk, 1) == Vector2i(6, 2), "and back again")
	_check(desk.fragment(0).rotation == 0, "to the original rotation")
	desk.rotate_fragment(0, false)
	_check(
		_pos(desk, 0) == Vector2i(2, 6) and _pos(desk, 1) == Vector2i(2, 2),
		"anticlockwise: B above A"
	)

	# A turn that would overlap, or leave the desk, is refused and changes nothing.
	desk = _trio()
	desk.add_parasite(9, PackedInt32Array([1, 1, 1, 1]))
	desk.place(0, Vector2i(2, 2))
	desk.place(1, Vector2i(6, 2))
	desk.place(9, Vector2i(2, 8))
	r = desk.rotate_fragment(0)
	_check(r.blocked == BLOCKED.OVERLAP, "a turn onto another fragment is refused")
	_check(
		_pos(desk, 1) == Vector2i(6, 2) and desk.fragment(0).rotation == 0, "and changes nothing"
	)
	desk = _pair()
	desk.place(0, Vector2i(0, 12))
	desk.place(1, Vector2i(4, 12))
	_check(desk.group_of(0).size() == 2, "a pair at the bottom edge of the desk")
	_check(desk.rotate_fragment(0).blocked == BLOCKED.OUT_OF_AREA, "a turn off the desk is refused")
	_check(_pos(desk, 1) == Vector2i(4, 12), "and changes nothing")


func _check_rotated_snap() -> void:
	print("— rotated snap —")
	var desk := _pair()
	desk.rotate_fragment(0)
	desk.rotate_fragment(1)
	desk.place(0, Vector2i(2, 2))
	# Turned a quarter clockwise, the page's east neighbour lies to the south.
	var r := desk.place(1, Vector2i(2, 7))
	var snap := _first_snap(r)
	_check(snap != null and snap.reason == OK, "both turned a quarter: B snaps below A")
	_check(_pos(desk, 1) == Vector2i(2, 6), "flush below")
	# Turned alike, but on the wrong side, the same sides do not fit.
	desk = _pair()
	desk.rotate_fragment(0)
	desk.rotate_fragment(1)
	desk.place(0, Vector2i(2, 2))
	r = desk.place(1, Vector2i(7, 2))
	_check(r.snaps.is_empty(), "turned a quarter, B east of A does not fit")
	# Different turns: a correct fragment beside its neighbour but not turned alike is not a match.
	desk = _pair()
	desk.place(0, Vector2i(2, 2))
	desk.rotate_fragment(1)
	desk.fragment(1).edges = PackedInt32Array([4, 9, 56, 5])
	# Turned a quarter clockwise, B's physical west side is its base south side.
	var shown := Edges.side_signature(desk.fragment(1).edges, 1, Edges.WEST)
	r = desk.place(1, Vector2i(7, 2))
	snap = _first_snap(r)
	_check(
		Edges.compatible(7, shown) == (snap != null),
		"a snap happens exactly when the turned sides fit"
	)
	_check(snap != null and snap.reason == MISMATCH, "fitting sides, different turn: MISMATCH")


func _check_group_move() -> void:
	print("— group move —")
	var desk := _trio()
	desk.add_parasite(9, PackedInt32Array([1, 1, 1, 1]))
	desk.place(0, Vector2i(2, 2))
	desk.place(1, Vector2i(6, 2))
	var r := desk.move(0, Vector2i.DOWN)
	_check(r.accepted(), "a group moves")
	_check(_pos(desk, 0) == Vector2i(2, 3) and _pos(desk, 1) == Vector2i(6, 3), "as one")
	r = desk.move(1, Vector2i.RIGHT)
	_check(
		_pos(desk, 0) == Vector2i(3, 3) and _pos(desk, 1) == Vector2i(7, 3), "from either member"
	)
	# The blocker stands in front of the member that is NOT the one being pushed.
	desk.place(9, Vector2i(12, 3))
	r = desk.move(0, Vector2i.RIGHT)
	_check(r.accepted() and _pos(desk, 1) == Vector2i(8, 3), "up to the blocker")
	r = desk.move(0, Vector2i.RIGHT)
	_check(r.blocked == BLOCKED.OVERLAP, "the group cannot overlap a third fragment")
	_check(_pos(desk, 0) == Vector2i(4, 3) and _pos(desk, 1) == Vector2i(8, 3), "and neither moved")
	_move_n(desk, 0, Vector2i.LEFT, 4)
	r = desk.move(1, Vector2i.LEFT)
	_check(r.blocked == BLOCKED.OUT_OF_AREA, "nor leave the desk")
	_check(not desk.return_to_new_area(0), "a bonded fragment cannot go back to the new area")
	_check(desk.return_to_new_area(9), "a lone one can")


# --------------------------------------------------------------------------
# Stain
# --------------------------------------------------------------------------


func _check_stain() -> void:
	print("— stain —")
	var desk := _trio()
	desk.add_parasite(9, PackedInt32Array([1, 1, 1, 1]))
	desk.place(0, Vector2i(2, 2))
	desk.place(1, Vector2i(6, 2))
	desk.place(9, Vector2i(12, 8))
	var rate := desk.balance.puzzle_stain_rate
	var cap := desk.balance.puzzle_stain_max
	desk.tick_handling(9, 1.0)
	_check(is_equal_approx(desk.fragment(9).stain, rate), "the stain rises with handling time")
	_check(desk.fragment(0).stain == 0.0, "only on what is handled")
	desk.tick_handling(9, 1.0)
	_check(is_equal_approx(desk.fragment(9).stain, 2.0 * rate), "and keeps rising")
	desk.tick_handling(9, 1.0e6)
	_check(
		is_equal_approx(desk.fragment(9).stain, cap) and cap < 1.0,
		"up to almost the whole fragment"
	)
	desk.fragment(0).stain = 0.0
	desk.fragment(1).stain = 0.0
	desk.tick_handling(0, 1.0)
	_check(
		(
			is_equal_approx(desk.fragment(0).stain, rate)
			and is_equal_approx(desk.fragment(1).stain, rate)
		),
		"a group is stained as one"
	)


# --------------------------------------------------------------------------
# A generated page
# --------------------------------------------------------------------------


func _check_generated_page() -> void:
	print("— generated page —")
	var desk := Desk.new(Vector2i(24, 16), 4, 5)
	desk.generate_page(2, 2, 2)
	_check(desk.ids().size() == 6, "four correct fragments and two parasites")
	_check(
		desk.fragment(5).is_parasitic() and not desk.fragment(3).is_parasitic(), "ids as documented"
	)
	var ok := true
	var positions := {0: Vector2i(2, 2), 1: Vector2i(6, 2), 2: Vector2i(2, 6), 3: Vector2i(6, 6)}
	for id in [0, 1, 2]:
		desk.place(id, positions[id])
	var last := desk.place(3, positions[3])
	var snap := _first_snap(last)
	ok = snap != null and snap.reason == OK and snap.completed
	_check(ok, "assembled from a generated page, in its page layout, it completes")
	_check(desk.fragment(4) == null and desk.fragment(5) == null, "and the parasites are gone")
