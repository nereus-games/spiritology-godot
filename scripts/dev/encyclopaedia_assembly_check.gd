## Headless check on the assembly screen's decisions (scripts/ui/encyclopaedia_assembly_logic.gd):
## selection and the grid, how a fragment enters the desk, the cursor, the report to the session,
## the layout saved in a page's `puzzle_state`, and the mapping between tiles and pixels.
##
## Run with: Godot --headless --path . res://scenes/dev/encyclopaedia_assembly_check.tscn
extends Node

const Logic := preload("res://scripts/ui/encyclopaedia_assembly_logic.gd")
const Fragment := preload("res://scripts/encyclopaedia/puzzle_fragment.gd")
const Results := preload("res://scripts/encyclopaedia/puzzle_results.gd")
const Model := preload("res://scripts/encyclopaedia/encyclopaedia_model.gd")

const SPECIES := &"kalilk"

var _fails: Array[String] = []


## A stand-in for the session that records what it is told.
class FakeSession:
	extends RefCounted
	var calls: Array = []

	func destroy_fragments(_s: StringName, _f: bool, count: int) -> int:
		calls.append(["destroy", count])
		return count

	func remove_parasitic_fragments(_s: StringName, _f: bool, count: int) -> int:
		calls.append(["parasites", count])
		return count

	func set_arranged_fragments(_s: StringName, _f: bool, count: int) -> void:
		calls.append(["arranged", count])

	func mark_page_assembled(_s: StringName, _f: bool = false) -> bool:
		calls.append(["assembled"])
		return true


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
	_check_building()
	_check_selection_and_grid()
	_check_entry()
	_check_blocked()
	_check_stain()
	_check_cursor()
	_check_report()
	_check_completing_the_page()
	_check_persistence()
	_check_reconciling()
	_check_geometry()
	GameSession.encyclopaedia.clear()
	print("")
	if _fails.is_empty():
		print("ALL OK")
	else:
		print("FAILURES: %s" % [_fails])
	get_tree().quit(0 if _fails.is_empty() else 1)


func _open(true_count: int, parasites: int, arranged: int = 0, state: Dictionary = {}) -> Variant:
	return Logic.open(SPECIES, false, state, true_count, parasites, arranged, false)


## Whether no two fragments on the desk overlap and all of them lie inside it.
func _tidy(logic: Variant) -> bool:
	var rects: Array[Rect2i] = []
	for id in logic.desk.ids():
		if logic.desk.fragment(id).area == Fragment.Area.DESK:
			var r: Rect2i = logic.desk.rect_of(id)
			if not Rect2i(Vector2i.ZERO, Logic.DESK_TILES).encloses(r):
				return false
			for other in rects:
				if r.intersects(other):
					return false
			rects.append(r)
	return true


func _check_building() -> void:
	print("[building a desk]")
	var model_frags: int = Model.FRAGMENTS_PER_PAGE
	_check(Logic.PAGE_FRAGMENTS == model_frags, "a page of 3 x 11 is the model's 33 fragments")
	var seed_a := Logic.seed_for(SPECIES, false)
	_check(seed_a == Logic.seed_for(SPECIES, false), "the seed is stable")
	_check(Logic.seed_for(SPECIES, false) != Logic.seed_for(SPECIES, true), "...per page")
	var logic: Variant = _open(6, 4)
	_check(logic.desk.ids().size() == 10, "6 true and 4 parasitic fragments on the desk")
	var all_new := true
	for id in logic.desk.ids():
		all_new = all_new and logic.desk.fragment(id).area == Fragment.Area.NEW
	_check(all_new, "all of them in the new fragment area")
	_check(logic.desk.arranged_count() == 0, "none arranged")
	_check(logic.desk.fragment(4).page_cell == Vector2i(1, 1), "fragment 4 belongs at cell (1, 1)")
	_check(logic.desk.fragment(100).is_parasitic(), "the first parasite is numbered 100")
	var again: Variant = _open(6, 4)
	_check(
		logic.desk.fragment(4).edges == again.desk.fragment(4).edges,
		"the sides come from the seed: the same on every opening"
	)
	var starting: Variant = _open(15, 0, 15)
	_check(starting.desk.arranged_count() == 15, "the starting duo's 15 fragments start arranged")
	_check(_tidy(starting), "...laid out on the desk, overlapping nothing")
	var thirty: Variant = _open(33, 33, 30)
	_check(thirty.desk.arranged_count() == 30 and _tidy(thirty), "30 arranged fit on the desk")
	_check(thirty.desk.group_of(0).size() == 30, "...as one group")


func _check_selection_and_grid() -> void:
	print("[selection and the grid]")
	var logic: Variant = _open(6, 2)
	_check(not logic.grid_visible(), "no grid while nothing is held")
	_check(not logic.select(999), "an unknown fragment cannot be selected")
	_check(logic.select(2), "a fragment of the new fragment area can be selected")
	_check(logic.grid_visible(), "the grid shows while one is held")
	_check(logic.desk.fragment(2).area == Fragment.Area.NEW, "selecting does not move it")
	logic.release()
	_check(not logic.grid_visible(), "the grid hides when it is let go")
	logic.select(2)
	var turned: Variant = logic.turn(true)
	_check(turned.accepted() and logic.desk.fragment(2).rotation == 1, "it turns where it lies")
	logic.turn(false)
	logic.turn(false)
	_check(logic.desk.fragment(2).rotation == 3, "a quarter turn either way")
	_check(logic.stash() == false, "a fragment already in the new area cannot be stashed")
	var idle: Variant = _open(2, 0).step(Vector2i.LEFT)
	_check(not idle.accepted() and not idle.entered, "nothing held: a move does nothing")
	logic.step(Vector2i.LEFT)
	_check(logic.stash(), "a lone fragment on the desk can be sent back")
	_check(
		logic.desk.fragment(2).area == Fragment.Area.NEW and not logic.is_selected(),
		"...to the new fragment area, and is let go"
	)


func _check_entry() -> void:
	print("[entering the desk]")
	var logic: Variant = _open(6, 2)
	logic.select(0)
	var first: Variant = logic.step(Vector2i.LEFT)
	var f: Fragment = logic.desk.fragment(0)
	_check(first.entered and first.accepted(), "the first move puts it on the desk")
	_check(f.area == Fragment.Area.DESK, "...in the manipulation area")
	var half := Vector2(Logic.FRAGMENT_TILES, Logic.FRAGMENT_TILES) / 2.0
	_check(Vector2(f.position) + half == Vector2(Logic.DESK_TILES) / 2.0, "...in the middle")
	logic.select(1)
	var second: Variant = logic.step(Vector2i.UP)
	_check(second.entered and second.snap == null, "the next one lands where nothing snaps")
	_check(not logic.desk.rect_of(1).grow(2).intersects(logic.desk.rect_of(0)), "...2 tiles clear")
	_check(_tidy(logic), "...and overlaps nothing")
	var from: Vector2i = logic.desk.fragment(1).position
	logic.step(Vector2i.RIGHT)
	_check(logic.desk.fragment(1).position == from + Vector2i.RIGHT, "then it moves a tile")
	# A desk with no room at all: 84 fragment-sized slots, all taken.
	var packed: Variant = _open(2, 90)
	var slot := 0
	for id in packed.desk.ids():
		if slot < 84:
			var tile := Vector2i(slot % 12, slot / 12) * Logic.FRAGMENT_TILES
			packed.desk.restore_fragment(id, Fragment.Area.DESK, tile, 0, false, 0.0)
		slot += 1
	_check(packed.entry_tile() == Logic.NO_TILE, "a full desk has no entry tile")
	packed.select(packed.desk.ids().back())
	var full: Variant = packed.step(Vector2i.LEFT)
	_check(full.desk_full and not full.entered, "...and the move says so")


func _check_blocked() -> void:
	print("[refused moves]")
	var logic: Variant = _open(6, 0)
	logic.select(0)
	logic.step(Vector2i.LEFT)
	var guard := 0
	var last: Variant = null
	while guard < 100:
		last = logic.step(Vector2i.LEFT)
		if not last.accepted():
			break
		guard += 1
	_check(last.blocked() == Results.MoveResult.Blocked.OUT_OF_AREA, "the desk's edge stops it")
	_check(logic.desk.fragment(0).position.x == 0, "...flush against it")
	# Two fragments side by side, and a third pushed into them.
	logic.desk.restore_fragment(1, Fragment.Area.DESK, Vector2i(10, 10), 0, false, 0.0)
	logic.desk.restore_fragment(2, Fragment.Area.DESK, Vector2i(14, 10), 0, false, 0.0)
	logic.release()
	logic.select(1)
	var bump: Variant = logic.step(Vector2i.RIGHT)
	_check(bump.blocked() == Results.MoveResult.Blocked.OVERLAP, "another fragment stops it")
	_check(logic.desk.fragment(1).position == Vector2i(10, 10), "...and nothing moved")


func _check_stain() -> void:
	print("[handling stains]")
	var logic: Variant = _open(3, 0)
	logic.handle(5.0)
	_check(logic.desk.fragment(0).stain == 0.0, "nothing held: no stain")
	logic.select(0)
	logic.handle(5.0)
	_check(logic.desk.fragment(0).stain > 0.0, "holding a fragment stains it")
	_check(logic.desk.fragment(1).stain == 0.0, "...and only it")
	logic.handle(1000.0)
	_check(
		logic.desk.fragment(0).stain <= logic.desk.balance.puzzle_stain_max,
		"the stain stops before covering the edges"
	)


func _check_cursor() -> void:
	print("[the cursor]")
	var centres := {1: Vector2(0, 0), 2: Vector2(100, 0), 3: Vector2(200, 5), 4: Vector2(100, 80)}
	_check(Logic.hop_target(centres, 1, Vector2.RIGHT) == 2, "right: the nearest ahead")
	_check(Logic.hop_target(centres, 2, Vector2.RIGHT) == 3, "...and on")
	_check(Logic.hop_target(centres, 2, Vector2.DOWN) == 4, "down")
	_check(Logic.hop_target(centres, 1, Vector2.DOWN) == 4, "...even a little sideways")
	_check(Logic.hop_target(centres, 3, Vector2.RIGHT) == 1, "off the right end: wraps to the left")
	_check(Logic.hop_target(centres, 4, Vector2.DOWN) == 2, "off the bottom: wraps to the top")
	_check(Logic.hop_target({1: Vector2.ZERO}, 1, Vector2.UP) == null, "alone: nowhere to hop")
	_check(Logic.hop_target(centres, 9, Vector2.UP) == null, "an unknown origin: nowhere")
	var logic: Variant = _open(4, 2)
	logic.ensure_cursor()
	_check(logic.cursor != null, "the cursor finds a fragment to rest on")
	_check(logic.cycle_order().size() == 6, "cycling visits every fragment")
	var seen := {}
	for i in 6:
		seen[logic.cursor] = true
		logic.cycle_cursor(1)
	_check(seen.size() == 6, "...once each")
	var back: Variant = logic.cursor
	logic.cycle_cursor(-1)
	logic.cycle_cursor(1)
	_check(logic.cursor == back, "backwards undoes forwards")
	var shuffled: Array = logic.new_area_order()
	_check(shuffled.size() == 6 and shuffled != [0, 1, 2, 3, 100, 101], "the new area is shuffled")
	_check(shuffled == _open(4, 2).new_area_order(), "...the same way every time")
	logic.select(0)
	logic.step(Vector2i.UP)
	_check(logic.cycle_order()[0] == 0, "fragments on the desk come first in cycling")
	_check(not logic.new_area_order().has(0), "...and leave the new area's order")


func _check_report() -> void:
	print("[reporting to the session]")
	var logic: Variant = _open(5, 3, 0)
	var session := FakeSession.new()
	logic.report_to(session, SPECIES, false)
	_check(session.calls == [["arranged", 0]], "a plain report is the arranged count")
	var outcome := Logic.Outcome.new()
	outcome.destroyed = [3, 4]
	outcome.parasites_removed = [100]
	outcome.parasites_cleared = [101, 102]
	outcome.completed = true
	session.calls.clear()
	logic.report_to(session, SPECIES, false, outcome)
	_check(
		session.calls == [["destroy", 2], ["parasites", 3], ["arranged", 0], ["assembled"]],
		"destroyed, vanished parasites, arranged count, then completion, in that order"
	)


func _check_completing_the_page() -> void:
	print("[completing a page through the real session]")
	GameSession.encyclopaedia.clear()
	GameSession.encyclopaedia.add_ifp(SPECIES, 99)
	var parasites := GameSession.parasitic_fragments(SPECIES)
	var logic: Variant = _open(Model.FRAGMENTS_PER_PAGE, parasites, 32)
	_check(logic.desk.arranged_count() == 32, "a page missing one fragment")
	logic.report_to(GameSession, SPECIES, false)
	_check(GameSession.arranged_fragments(SPECIES) == 32, "the session is told: 32 arranged")
	_check(GameSession.page_ifp(SPECIES) == 99, "...99 %")
	_check(not GameSession.is_page_complete(SPECIES), "...not complete")
	# The last one: turned like the block, then carried to its place beside it.
	logic.select(32)
	logic.turn(true)
	var goal := Vector2i(1, 1) + Vector2i(0, 2 * Logic.FRAGMENT_TILES)
	var outcome: Variant = null
	var guard := 0
	while guard < 200 and (outcome == null or outcome.snap == null):
		var here: Vector2i = logic.desk.fragment(32).position
		var dir := Vector2i.ZERO
		if logic.desk.fragment(32).area == Fragment.Area.NEW:
			dir = Vector2i.LEFT
		elif here.x != goal.x:
			dir = Vector2i(signi(goal.x - here.x), 0)
		else:
			dir = Vector2i(0, signi(goal.y - here.y))
		outcome = logic.step(dir)
		guard += 1
	_check(outcome != null and outcome.snap != null, "carrying it home snaps it")
	_check(outcome.snap.reason == Results.SnapResult.Reason.OK, "...correctly")
	_check(outcome.completed and logic.desk.complete, "the page is complete")
	logic.report_to(GameSession, SPECIES, false, outcome)
	_check(GameSession.arranged_fragments(SPECIES) == 33, "the session is told: 33 arranged")
	_check(GameSession.is_page_complete(SPECIES), "...and marked assembled: 100 %")
	_check(GameSession.parasitic_fragments(SPECIES) == 0, "the parasites are gone")
	GameSession.encyclopaedia.clear()


func _check_persistence() -> void:
	print("[saving the layout]")
	var logic: Variant = _open(12, 5, 6)
	logic.select(7)
	logic.step(Vector2i.LEFT)
	logic.step(Vector2i.LEFT)
	logic.turn(true)
	logic.handle(10.0)
	logic.desk.fragment(8).damaged = true
	logic.select(9)
	logic.turn(false)
	var state: Dictionary = logic.save_state()
	var wire: Variant = JSON.parse_string(JSON.stringify(state))
	_check(wire is Dictionary, "the state survives JSON")
	var back: Variant = Logic.open(SPECIES, false, wire, 12, 5, 6, false)
	var same: bool = back.desk.ids().size() == logic.desk.ids().size()
	for id in logic.desk.ids():
		var a: Fragment = logic.desk.fragment(id)
		var b: Fragment = back.desk.fragment(id)
		same = (
			same
			and b != null
			and a.area == b.area
			and a.rotation == b.rotation
			and a.damaged == b.damaged
			and is_equal_approx(a.stain, b.stain)
			and a.edges == b.edges
			and a.page_cell == b.page_cell
			and (a.area != Fragment.Area.DESK or a.position == b.position)
		)
	_check(same, "every fragment comes back as it was: area, place, turn, damage, stain, sides")
	_check(back.desk.bond_pairs() == logic.desk.bond_pairs(), "...and the bonds")
	_check(back.desk.arranged_count() == 6, "...so the arranged count")
	_check(back.next_parasite == logic.next_parasite, "...and the next parasite's number")
	_check(back.opens == logic.opens + 1, "opening it again is counted")
	_check(back.page_seed == logic.page_seed, "the seed is kept")
	var model := Model.new()
	model.set_puzzle_state(SPECIES, false, state)
	var model2 := Model.new()
	model2.from_dict(JSON.parse_string(JSON.stringify(model.to_dict())))
	var kept: Dictionary = model2.puzzle_state(SPECIES, false)
	_check(int(kept.get("seed", 0)) == int(state["seed"]), "...and through the model's own save")
	_check(Model.new().puzzle_state(SPECIES, false).is_empty(), "a page never touched has no state")
	var junk: Variant = _open(4, 1, 0, {"version": 9})
	_check(junk.desk.ids().size() == 5, "an unknown version starts afresh")
	var broken := {"version": 1, "fragments": [{"id": 500}]}
	_check(_open(4, 0, 0, broken).desk.ids().size() == 4, "so does a broken one")


func _check_reconciling() -> void:
	print("[bringing a saved layout in line with the model]")
	var state: Dictionary = _open(6, 2).save_state()
	var more: Variant = _open(9, 4, 0, state)
	_check(more.desk.ids().size() == 13, "new IFP: fragments are added")
	_check(more.desk.fragment(8).area == Fragment.Area.NEW, "...to the new fragment area")
	_check(more.next_parasite == 104, "...and new parasites are numbered after the old ones")
	_check(_open(3, 0, 0, state).desk.ids().size() == 3, "more saved than the model has: afresh")
	var plain: Dictionary = _open(15, 0, 0).save_state()
	_check(_open(15, 0, 15, plain).desk.arranged_count() == 15, "fewer arranged than said: afresh")
	var live: Variant = _open(3, 1)
	var added: Array = live.add_new_fragments(6, 2)
	_check(
		added.size() == 4 and added.has(5) and added.has(101), "fragments formed while open join"
	)
	var done: Variant = Logic.open(SPECIES, false, {}, 33, 0, 33, true)
	_check(done.desk.complete and done.desk.group_of(0).size() == 33, "an assembled page is whole")
	_check(_tidy(done) and done.desk.arranged_count() == 33, "...and lies on the desk")
	# A destroyed fragment leaves a gap that the desk still knows about.
	var minus: Variant = _open(32, 0)
	_check(not minus.desk.has_fragment(32), "a page missing a fragment")
	_check(minus.desk.completion() == 0.0, "...counts it in its total")


func _check_geometry() -> void:
	print("[tiles, pixels and slots]")
	var area := Rect2(28, 60, 960, 560)
	var rect := Logic.desk_rect(area)
	_check(area.encloses(rect), "the desk fits its area")
	var wide := rect.size.x / Logic.DESK_TILES.x
	_check(is_equal_approx(wide, rect.size.y / Logic.DESK_TILES.y), "...with square tiles")
	_check(is_equal_approx(rect.get_center().x, area.get_center().x), "...centred")
	var px := Logic.tile_px_for(area.size)
	var round_trip := true
	for y in Logic.DESK_TILES.y:
		for x in Logic.DESK_TILES.x:
			var tile := Vector2i(x, y)
			var pixel := Logic.tile_to_px(tile, px, rect.position)
			round_trip = round_trip and Logic.px_to_tile(pixel, px, rect.position) == tile
	_check(round_trip, "tile to pixel and back, for every tile")
	var nudged := Logic.tile_to_px(Vector2i(5, 7), px, rect.position) + Vector2(px, px) * 0.3
	_check(Logic.px_to_tile(nudged, px, rect.position) == Vector2i(5, 7), "a pixel near a corner")
	var panel := Rect2(0, 0, 250, 560)
	var previous := 1000.0
	for count in [1, 6, 20, 40, 66]:
		var layout := Logic.slot_layout(panel.size, count, 80.0)
		var fits: bool = layout["slot"] > 0.0 and layout["cols"] * layout["rows"] >= count
		var inside := true
		var rects: Array[Rect2] = []
		for i in count:
			var r := Rect2(Logic.slot_position(i, layout, panel), Vector2.ONE * layout["slot"])
			inside = inside and panel.grow(0.01).encloses(r)
			for other in rects:
				inside = inside and not r.intersects(other)
			rects.append(r)
		_check(fits and inside, "%d slots fit the new fragment area, overlapping nothing" % count)
		_check(layout["slot"] <= previous, "...no bigger than for fewer")
		previous = layout["slot"]
