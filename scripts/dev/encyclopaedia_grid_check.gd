## Headless check on the encyclopaedia grid's rules: wrap-around, the selector never resting on
## an undiscovered species, the down/right tie-break, the start position and the icon states.
## Pure logic over `encyclopaedia_grid_logic.gd`, with the screen's data feed checked at the end.
##
## Run with: Godot --headless --path . res://scenes/dev/encyclopaedia_grid_check.tscn
extends Node

const Logic := preload("res://scripts/ui/encyclopaedia_grid_logic.gd")
const Source := preload("res://scripts/ui/encyclopaedia_page_source.gd")
const Sample := preload("res://scripts/dev/encyclopaedia_sample.gd")

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
	_check_icon_states()
	_check_wrap()
	_check_wrap_partial_row()
	_check_nearest()
	_check_tie_break()
	_check_never_rests_on_undiscovered()
	_check_start()
	_check_feed()
	print("")
	if _fails.is_empty():
		print("ALL OK")
	else:
		print("FAILURES: %s" % [_fails])
	get_tree().quit(0 if _fails.is_empty() else 1)


## A 3 x 3 grid from a picture: "x" discovered, "." not.
func _grid(rows: Array) -> Array:
	var cells: Array = []
	for row in rows:
		for ch in String(row):
			cells.append(ch == "x")
	return cells


func _check_icon_states() -> void:
	print("[icon states]")
	_check(Logic.icon_state(0) == Logic.IconState.NONE, "0 IFP: no icon")
	_check(Logic.icon_state(1) == Logic.IconState.BLACK, "1 IFP: black")
	_check(Logic.icon_state(44) == Logic.IconState.BLACK, "44 IFP: black")
	_check(Logic.icon_state(45) == Logic.IconState.GRAY, "45 IFP: grayscale")
	_check(Logic.icon_state(99) == Logic.IconState.GRAY, "99 IFP: still grayscale")
	_check(Logic.icon_state(100) == Logic.IconState.COLOUR, "100 (assembled): full colour")


func _check_wrap() -> void:
	print("[wrapping]")
	var all := _grid(["xxx", "xxx", "xxx"])
	_check(Logic.move(3, all, 0, Vector2i.LEFT) == 2, "left off the first column: last column")
	_check(Logic.move(3, all, 2, Vector2i.RIGHT) == 0, "right off the last column: first column")
	_check(Logic.move(3, all, 1, Vector2i.UP) == 7, "up off the top: bottom row")
	_check(Logic.move(3, all, 7, Vector2i.DOWN) == 1, "down off the bottom: top row")
	_check(Logic.move(3, all, 4, Vector2i.RIGHT) == 5, "an ordinary step")


func _check_wrap_partial_row() -> void:
	print("[wrapping with a last row that is not full]")
	var all := _grid(["xxx", "xxx", "x"])
	_check(Logic.wrapped_step(3, 7, 6, Vector2i.RIGHT) == 6, "a row of one cell wraps onto itself")
	_check(Logic.wrapped_step(3, 7, 0, Vector2i.UP) == 6, "up off the top of a long column")
	_check(Logic.wrapped_step(3, 7, 1, Vector2i.UP) == 4, "up off the top of a short column")
	_check(Logic.wrapped_step(3, 7, 4, Vector2i.DOWN) == 1, "down off a short column's end")
	_check(Logic.move(3, all, 2, Vector2i.DOWN) == 5, "down within a short column")


func _check_nearest() -> void:
	print("[nearest discovered]")
	var g := _grid(["x..", "...", "..x"])
	_check(Logic.nearest_discovered(3, g, 1) == 0, "closest to the top middle")
	_check(Logic.nearest_discovered(3, g, 7) == 8, "closest to the bottom middle")
	_check(Logic.nearest_discovered(3, _grid(["...", "...", "..."]), 4) == -1, "nothing discovered")
	_check(Logic.nearest_discovered(3, _grid(["x..", "...", "..."]), 4, 0) == 0, "the excluded cell, when alone in its reach")
	# Moving right from a lone discovered cell, with another further away: it moves on.
	var far := _grid(["x...", "....", "...x"])
	_check(Logic.move(4, far, 0, Vector2i.RIGHT) == 11, "pushed against a gap, it goes to the next")


func _check_tie_break() -> void:
	print("[ties go down, then right]")
	# Target (1,1) in the middle; candidates above and below it, equally close.
	var vertical := _grid([".x.", "...", ".x."])
	_check(Logic.nearest_discovered(3, vertical, 4) == 7, "above or below: below")
	# Target (1,1); candidates left and right.
	var horizontal := _grid(["...", "x.x", "..."])
	_check(Logic.nearest_discovered(3, horizontal, 4) == 5, "left or right: right")
	# Target (1,1); candidates up and right: down/right means the lower, which is the right one.
	var corner := _grid([".x.", "..x", "..."])
	_check(Logic.nearest_discovered(3, corner, 4) == 5, "up or right: right, the lower of the two")
	# Target (1,1); candidates up and left: the lower one is the left one.
	var corner2 := _grid([".x.", "x..", "..."])
	_check(Logic.nearest_discovered(3, corner2, 4) == 3, "up or left: left, the lower of the two")


func _check_never_rests_on_undiscovered() -> void:
	print("[the selector never rests on an undiscovered species]")
	var g := _grid(["x.x.", ".x..", "..x.", "x..x"])
	var bad := 0
	var dirs := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	for from in g.size():
		if not g[from]:
			continue
		for d in dirs:
			var to := Logic.move(4, g, from, d)
			if to < 0 or not g[to]:
				bad += 1
	_check(bad == 0, "every step from every discovered cell lands on a discovered one")
	# A long random walk, for good measure.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var at := 0
	var ok := true
	for i in 500:
		at = Logic.move(4, g, at, dirs[rng.randi() % 4])
		ok = ok and g[at]
	_check(ok, "a 500-step walk never lands on an undiscovered cell")
	_check(Logic.move(3, _grid(["...", "...", "..."]), 0, Vector2i.RIGHT) == 0, "an empty grid")


func _check_start() -> void:
	print("[start position]")
	var g := _grid(["x..", ".x.", "..x"])
	_check(Logic.start_index(3, g, 4) == 4, "starts on the last examined species")
	_check(Logic.start_index(3, g, 5) == 8, "if it is not discovered: nearest, down/right on a tie")
	_check(Logic.start_index(3, g, -1) == 0, "no last examined: the first discovered")
	_check(Logic.start_index(3, _grid(["...", "...", "..."]), 4) == -1, "empty encyclopaedia")


func _check_feed() -> void:
	print("[the page source, on the sample progress]")
	var saved: Dictionary = GameSession.encyclopaedia_ifp.duplicate()
	Sample.fill()
	var species: Array = GameData.all_species()
	_check(species.size() >= 30, "the data has its species (%d)" % species.size())
	var states := {}
	for sp in species:
		states[Logic.icon_state(GameSession.encyclopaedia_ifp.get(sp.id, 0))] = true
	_check(states.size() == 4, "the sample shows every icon state")
	var any_id: StringName = species[0].id
	var info := Source.build(any_id)
	_check(info.weaknesses.size() == 3, "a page has three weaknesses")
	_check(info.completion == int(GameSession.encyclopaedia_ifp.get(any_id, 0)), "completion")
	var none_unlocked := true
	for sp in species:
		none_unlocked = none_unlocked and Source.unlocked_abilities(sp.id).is_empty()
	_check(none_unlocked, "no ability is unlocked while no fragment model exists")
	GameSession.encyclopaedia_ifp = saved
