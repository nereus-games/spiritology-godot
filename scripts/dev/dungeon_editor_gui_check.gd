## Headless check of the dungeon editor's screen: the property form built from the kinds table, the
## screen driven by input events and its public methods (tools, strokes, the inspector, undo, the
## issues list, saving and leaving), what it does on a partial, a missing and a huge dungeon, and
## the translations of everything it says.
##
## The writer and the model are checked by `dungeon_editor_check`. Nothing here writes into
## `data/`: saves go to a temporary directory.
##
## Run with: Godot --headless --path . res://scenes/dev/dungeon_editor_gui_check.tscn
## As a start scene rather than --script; see geometry_check.gd.
extends Node

const Kinds := preload("res://scripts/dungeon/dungeon_kinds.gd")
const Model := preload("res://scripts/dungeon/editor/dungeon_editor_model.gd")
const Form := preload("res://scripts/dungeon/editor/dungeon_prop_form.gd")
const Util := preload("res://scripts/dungeon/editor/dungeon_editor_util.gd")
const Validator := preload("res://scripts/dungeon/dungeon_validator.gd")
const SCREEN := preload("res://scenes/dev/dungeon_editor.tscn")

const LAKE := &"norgzevod_frozen_lake"
const TEMP := "user://dungeon_editor_gui_check/"

var _fails: Array[String] = []


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  OK   %s" % label)
	else:
		print("  FAIL %s" % label)
		_fails.append(label)


func _ready() -> void:
	await get_tree().process_frame
	_clean_temp()
	_check_form()
	await _check_gui()
	await _check_gui_edge_cases()
	_check_translations()
	_clean_temp()
	print("")
	if _fails.is_empty():
		print("ALL OK")
	else:
		print("FAILURES: %s" % [_fails])
	get_tree().quit(0 if _fails.is_empty() else 1)


# --------------------------------------------------------------------------
# The form
# --------------------------------------------------------------------------


func _check_form() -> void:
	print("-- the property form, built from the kinds table")
	for kind in Kinds.KINDS:
		var box := VBoxContainer.new()
		var current := {}
		Form.build(box, kind, func(): return current, 0, func(_n, _s): pass, func(_a, _b): pass)
		var props: Dictionary = Kinds.KINDS[kind]["props"]
		var ok := true
		for name in props:
			var row: Control = box.get_node_or_null("Row_" + name)
			if row == null:
				ok = false
				continue
			var widget: Control = row.get_child(2)
			var type: String = props[name]
			if type.begins_with("enum:"):
				ok = ok and widget is OptionButton
			elif type == "bool":
				ok = ok and widget is CheckBox
			elif type == "int" or type == "float":
				ok = ok and widget is SpinBox
			elif type == "str" or type == "list":
				ok = ok and widget is LineEdit
			elif type == "dir":
				ok = ok and widget is HBoxContainer and widget.get_child_count() == 4
			elif type == "tile" or type == "tiles":
				ok = ok and widget is HBoxContainer and widget.get_child(0) is LineEdit
				ok = ok and widget.get_child(1) is Button
			else:
				ok = false
		_check(ok, "%s: one row per property, the widget its type asks for" % kind)
		var commons := true
		for name in Kinds.COMMON:
			commons = commons and box.get_node_or_null("Row_" + name) != null
		_check(commons, "%s: the common properties too" % kind)
		_check(box.get_node_or_null("CustomRow") != null, "%s: a row for custom properties" % kind)
		box.free()
	# A set property is shown set, and a change comes back as the complete new properties.
	var box2 := VBoxContainer.new()
	var got := []
	var current2 := {"trapped": true, "loot": ["a", "b"], "note": "hi"}
	Form.build(
		box2,
		&"chest",
		func(): return current2,
		0,
		func(n, s): got.append([n, s]),
		func(_a, _b): pass
	)
	_check(
		(box2.get_node("Row_trapped").get_child(2) as CheckBox).button_pressed,
		"a set bool is checked"
	)
	_check(
		(box2.get_node("Row_loot").get_child(2) as LineEdit).text == "a,b",
		"a list reads back joined"
	)
	_check(box2.get_node("Row_loot_min").modulate.a < 1.0, "an unset property is dimmed")
	# (A SpinBox outside the tree does not announce a value set from code: emit what the user's
	# click on its arrows would.)
	(box2.get_node("Row_loot_min").get_child(2) as SpinBox).value_changed.emit(4.0)
	_check(
		(
			got.size() == 1
			and got[0][0] == {"trapped": true, "loot": ["a", "b"], "note": "hi", "loot_min": 4}
		),
		"an edit hands over every property"
	)
	(box2.get_node("Row_note").get_child(0) as Button).pressed.emit()
	_check(
		got.size() == 2 and not got[1][0].has("note") and got[1][1],
		"the clear button removes it, and asks for a rebuild"
	)
	box2.free()
	_check(
		Form.names_for(&"", {"custom.x": "1"}).has("custom.x"),
		"a custom property of a bare tile is listed"
	)
	_check(not Form.names_for(&"trap", {}).has("loot"), "...and a kind's own properties only")


# --------------------------------------------------------------------------
# The screen
# --------------------------------------------------------------------------


func _lake_screen() -> Control:
	var m := Model.new()
	m.load_dungeon(LAKE)
	m.root = TEMP
	var screen := SCREEN.instantiate()
	screen.model = m
	screen.navigate = false
	add_child(screen)
	await get_tree().process_frame
	await get_tree().process_frame
	return screen


func _mouse(screen: Control, tile: Vector3i, pressed: bool, shift: bool = false) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = screen.view.tile_center(tile)
	e.shift_pressed = shift
	screen.view._gui_input(e)


func _move(screen: Control, tile: Vector3i) -> void:
	var e := InputEventMouseMotion.new()
	e.position = screen.view.tile_center(tile)
	screen.view._gui_input(e)


func _click(screen: Control, tile: Vector3i, shift: bool = false) -> void:
	_mouse(screen, tile, true, shift)
	_mouse(screen, tile, false, shift)


## Presses on the first tile, drags through the others and lets go on the last.
func _drag(screen: Control, tiles: Array, shift: bool = false) -> void:
	_mouse(screen, tiles[0], true, shift)
	for t in tiles.slice(1):
		_move(screen, t)
	_mouse(screen, tiles[-1], false, shift)


func _key(screen: Control, code: Key, ctrl: bool = false, shift: bool = false) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	e.ctrl_pressed = ctrl
	e.shift_pressed = shift
	screen._unhandled_key_input(e)


func _free_floor(m: Model, y: int, skip: int = 0) -> Vector3i:
	var n := 0
	var keys: Array = m.plan.floor_tiles.keys()
	keys.sort()
	for t in keys:
		if t.y == y and m.placements_at(t).is_empty() and not m.plan.tile_props.has(t):
			if n == skip:
				return t
			n += 1
	return Vector3i(-1, y, -1)


func _count_stairs_at(m: Model, tile: Vector3i) -> int:
	var n := 0
	for p in m.plan.placements:
		if p["kind"] == &"stairs" and p["tile"].x == tile.x and p["tile"].z == tile.z:
			n += 1
	return n


func _check_gui() -> void:
	print("-- the screen")
	var screen: Control = await _lake_screen()
	var m: Model = screen.model
	_check(screen.view != null and screen.view.model == m, "the map is bound to the model")
	for kind in Kinds.KINDS:
		_check(
			screen._tool_buttons.has("kind:" + String(kind)),
			"the palette has %s, from the table" % kind
		)
	for terrain in Model.TERRAINS:
		_check(
			screen._tool_buttons.has("terrain:" + String(terrain)), "the palette has %s" % terrain
		)
	for id in [
		"select", "erase", "entrance", "exit", "exit_remove", "zone_paint", "zone_erase", "emerge"
	]:
		_check(screen._tool_buttons.has(id), "the palette has the %s tool" % id)
	_check(screen._tool_buttons["select"].button_pressed, "select is the tool at the start")
	for y in m.floors:
		_check(
			screen._floor_bar.get_node_or_null("Floor_%d" % y) != null, "a button for floor %d" % y
		)
	_check(screen.title_label.text.contains("Norgz") and not m.dirty, "the title names the dungeon")
	_check(screen.undo_button.disabled and screen.redo_button.disabled, "nothing to undo yet")

	# Floors: the buttons, the number keys.
	screen.set_floor(1)
	_check(screen.view.floor_y == 1 and screen.floor_y == 1, "set_floor changes the floor shown")
	_key(screen, KEY_3)
	_check(screen.floor_y == 0, "the 3rd number key shows the 3rd floor (0)")
	_key(screen, KEY_1)
	_check(screen.floor_y == -2, "the 1st shows the lowest")
	screen._floor_bar.get_node("Floor_1").pressed.emit()
	_check(screen.floor_y == 1, "a floor button shows its floor")
	screen.set_floor(0)

	# Painting: a stroke is one command.
	screen.select_tool("terrain:wall")
	var a := _free_floor(m, 0, 3)
	var line: Array = []
	for i in 4:
		line.append(a + Vector3i(i, 0, 0))
	var depth := m._undo.size()
	_drag(screen, line)
	_check(m._undo.size() == depth + 1, "a stroke of four tiles is one command")
	var painted := 0
	for t in line:
		if m.plan.wall_tiles.has(t):
			painted += 1
	_check(painted == 4, "...and painted every tile it crossed")
	_check(m.dirty, "the model is dirty")
	_check(
		screen.title_label.text.contains(
			TranslationServer.translate("UI_DEV_EDITOR_DIRTY").strip_edges()
		),
		"the title says so"
	)
	_check(not screen.undo_button.disabled, "undo is available")
	_key(screen, KEY_Z, true)
	_check(not m.plan.wall_tiles.has(line[0]), "Ctrl+Z undoes the stroke")
	_key(screen, KEY_Y, true)
	_check(m.plan.wall_tiles.has(line[0]), "Ctrl+Y redoes it")
	_key(screen, KEY_Z, true)
	_key(screen, KEY_Z, true, true)
	_check(m.plan.wall_tiles.has(line[0]), "Ctrl+Shift+Z redoes too")
	_key(screen, KEY_Z, true)
	# A fast drag leaves no gap.
	var far: Vector3i = line[0] + Vector3i(6, 0, 0)
	_mouse(screen, line[0], true)
	_move(screen, far)
	_mouse(screen, far, false)
	var gaps := 0
	for i in 7:
		if not m.plan.wall_tiles.has(line[0] + Vector3i(i, 0, 0)):
			gaps += 1
	_check(gaps == 0, "a drag that jumps tiles still paints the line between")
	_key(screen, KEY_Z, true)
	# A rectangle with Shift.
	var b := _free_floor(m, 0, 10)
	screen.select_tool("terrain:ice")
	_drag(screen, [b, b + Vector3i(2, 0, 1)], true)
	var iced := 0
	for t in Util.rect_tiles(b, b + Vector3i(2, 0, 1)):
		if m.terrain_of(t) == &"ice":
			iced += 1
	_check(iced == 6, "Shift and drag fills the rectangle")
	_key(screen, KEY_Z, true)
	_check(m.terrain_of(b) == &"floor", "...in one command")

	# Placing from the palette, and the inspector.
	var spot := _free_floor(m, 0, 20)
	screen.select_tool("kind:chest")
	_click(screen, spot)
	var placed: Array = m.placements_at(spot)
	_check(
		placed.size() == 1 and placed[0]["kind"] == &"chest", "a click with a kind's tool places it"
	)
	var uid: int = placed[0]["uid"]
	_check(screen._sel_uid == uid, "...and selects it")
	var row: Control = screen._sel_box.find_child("Row_trapped", true, false)
	_check(row != null, "the inspector has the kind's properties")
	(row.get_child(2) as CheckBox).button_pressed = true
	await get_tree().process_frame
	_check(
		m.placement(uid)["props"].get("trapped", false) == true, "ticking a box edits the placement"
	)
	var loot: LineEdit = screen._sel_box.find_child("Row_loot", true, false).get_child(2)
	loot.text = "rune_stone, spade"
	loot.text_submitted.emit(loot.text)
	_check(
		m.placement(uid)["props"]["loot"] == ["rune_stone", "spade"],
		"a list is typed comma-separated"
	)
	_check(m.placement(uid)["props"]["trapped"] == true, "...and the earlier edit survives it")
	var note: LineEdit = screen._sel_box.find_child("Row_note", true, false).get_child(2)
	note.text = "hello"
	note.text_submitted.emit("hello")
	_check(m.placement(uid)["props"]["note"] == "hello", "a note is a property like the others")
	_key(screen, KEY_Z, true)
	_check(not m.placement(uid)["props"].has("note"), "an edit from the form undoes")
	_key(screen, KEY_DELETE)
	await get_tree().process_frame
	_check(m.placements_at(spot).is_empty(), "Delete removes the selected placement")
	# Picking a tile on the map for a property.
	var gate_tile := Vector3i(-1, 0, -1)
	for p in m.plan.placements:
		if p["kind"] == &"gate" and p["tile"].y == 0:
			gate_tile = p["tile"]
	screen.select_tool("select")
	_click(screen, gate_tile)
	var arrival: Control = screen._sel_box.find_child("Row_arrival", true, false)
	_check(arrival != null, "a gate has an arrival row")
	(arrival.get_child(2).get_child(1) as Button).pressed.emit()
	_check(screen.view.picking, "the pick button waits for a click on the map")
	var target := _free_floor(m, 0, 30)
	var gate_uid: int = screen._sel_uid
	_click(screen, target)
	_check(
		m.placement(gate_uid)["props"].get("arrival") == target, "the click sets the tile property"
	)
	_check(not screen.view.picking, "...and ends the picking")
	var edge_row: Control = screen._sel_box.find_child("Row_edge", true, false)
	var west: Button = edge_row.get_child(2).get_child(3)
	west.button_pressed = true
	west.pressed.emit()
	_check(
		m.placement(gate_uid)["props"]["edge"] == Kinds.DIRECTIONS["W"],
		"the N E S W buttons set a direction"
	)
	var type_row: Control = screen._sel_box.find_child("Row_type", true, false)
	(type_row.get_child(2) as OptionButton).item_selected.emit(3)
	_check(m.placement(gate_uid)["props"]["type"] == "teleport", "a drop-down sets an enum")
	await get_tree().process_frame
	# Esc deselects.
	_key(screen, KEY_ESCAPE)
	_check(screen._sel_uid == -1 and not screen._has_sel, "Esc deselects")
	_click(screen, spot)
	_check(screen._has_sel and screen._sel_tile == spot, "the select tool selects a tile")
	_check(
		screen._sel_box.find_child("Row_note", true, false) != null,
		"...and shows its own properties"
	)
	var tag: LineEdit = screen._sel_box.find_child("Row_tags", true, false).get_child(2)
	tag.text = "unreachable_ok"
	tag.text_submitted.emit(tag.text)
	_check(m.plan.tile_props[spot]["tags"] == ["unreachable_ok"], "a bare tile's tags are edited")
	_key(screen, KEY_Z, true)

	# Stairs come in pairs.
	var st := _free_floor(m, 0, 40)
	screen.select_tool("kind:stairs")
	_check(
		screen._tool_box.find_child("PartnerCheck", true, false) != null,
		"the stairs tool offers the pair"
	)
	_click(screen, st)
	_check(_count_stairs_at(m, st) == 2, "a flight is placed with its partner on the next floor")
	_check(screen.status_label.text != "", "...and the status line says where")
	_key(screen, KEY_Z, true)
	screen._stairs_partner = false
	_click(screen, st)
	_check(_count_stairs_at(m, st) == 1, "with the box unticked, only the one")
	_key(screen, KEY_Z, true)
	screen._stairs_partner = true

	# Entrance, exits, erase, zones, emerge.
	var e1 := _free_floor(m, 0, 50)
	screen.select_tool("entrance")
	screen._entrance_facing = "S"
	screen._entrance_edge = "N"
	_click(screen, e1)
	_check(
		m.plan.entrance == e1 and m.plan.tile_props[e1]["facing"] == Kinds.DIRECTIONS["S"],
		"the entrance tool places it, facing set"
	)
	_key(screen, KEY_Z, true)
	var x1 := _free_floor(m, 0, 60)
	screen.select_tool("exit")
	screen._exit_edge = "E"
	_click(screen, x1)
	_check(
		m.plan.exits.has(x1) and m.plan.tile_props[x1]["exit_edge"] == Kinds.DIRECTIONS["E"],
		"the exit tool adds one with its edge"
	)
	screen.select_tool("exit_remove")
	_click(screen, x1)
	_check(not m.plan.exits.has(x1), "the remove-exit tool takes it away")
	screen.select_tool("kind:trap")
	_click(screen, spot)
	_check(m.placements_at(spot).size() == 1, "(a trap, to erase)")
	screen.select_tool("erase")
	_click(screen, spot)
	_check(m.placements_at(spot).is_empty(), "the eraser removes the placement")
	screen.select_tool("zone_paint")
	screen.create_zone("t")
	_check(m.plan.zones.has("t"), "a zone is created from the tool's options")
	_drag(screen, [a, a + Vector3i(2, 0, 0)])
	_check(m.plan.zones["t"]["tiles"].size() == 3, "dragging paints tiles into the zone")
	screen.select_tool("zone_erase")
	_click(screen, a)
	_check(m.plan.zones["t"]["tiles"].size() == 2, "the zone eraser takes one out")
	screen.create_zone("t")
	_check(
		screen.status_label.text == TranslationServer.translate("UI_DEV_EDITOR_ERR_ZONE_EXISTS"),
		"a refused operation says why, translated"
	)
	screen.select_tool("emerge")
	var em := _free_floor(m, 0, 70)
	_click(screen, em)
	_check(m.emerge_tile() == em, "the emerge tool sets the tile")

	# The hover line.
	_move(screen, Vector3i(27, 0, 23))
	_check(
		screen.hover_label.text.begins_with("AB24"),
		"hovering says the cell name: %s" % screen.hover_label.text
	)
	_move(screen, Vector3i(24, 0, 8))
	_check(
		screen.hover_label.text.contains(screen.kind_label(&"trap")), "...and what is on the tile"
	)

	# Zoom and pan.
	var z0: float = screen.view.zoom
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = screen.view.size * 0.5
	screen.view._gui_input(wheel)
	_check(screen.view.zoom > z0, "the wheel zooms in")
	var anchor: Vector3i = screen.view.tile_at(wheel.position)
	screen.view._gui_input(wheel)
	_check(screen.view.tile_at(wheel.position) == anchor, "...around the cursor")
	var o0: Vector2 = screen.view.origin
	var mid := InputEventMouseButton.new()
	mid.button_index = MOUSE_BUTTON_MIDDLE
	mid.pressed = true
	mid.position = Vector2(100, 100)
	screen.view._gui_input(mid)
	var drag := InputEventMouseMotion.new()
	drag.position = Vector2(130, 120)
	screen.view._gui_input(drag)
	mid.pressed = false
	screen.view._gui_input(mid)
	_check(screen.view.origin == o0 + Vector2(30, 20), "the middle button pans")

	# Validation, and the issues.
	while m.can_undo():
		m.undo()
	var issues: Array = screen.validate()
	var waived := 0
	var errors := 0
	for i in issues:
		if i.has("waived"):
			waived += 1
		elif i["severity"] == "error":
			errors += 1
	_check(
		screen.issue_list.get_child_count() == issues.size() and waived > 0, "one button per issue"
	)
	var waived_color := Color.WHITE
	for i in issues.size():
		var btn: Button = screen.issue_list.get_child(i)
		if issues[i].has("waived"):
			waived_color = btn.get_theme_color("font_color")
			_check(
				btn.text.contains(TranslationServer.translate("UI_DEV_EDITOR_SEVERITY_WAIVED")),
				"a waived issue is labelled so"
			)
	_check(errors == 0, "the lake has no unwaived error")
	m.create_zone("calm", ["safe"])
	var hazard := _free_floor(m, 1, 0)
	m.zone_paint("calm", [hazard])
	m.place(&"trap", hazard, {"type": "poison"})
	screen.set_floor(0)
	issues = screen.validate()
	var hit := -1
	var err_color := Color.WHITE
	for i in issues.size():
		if issues[i]["code"] == "SAFE_HAZARD":
			hit = i
			err_color = screen.issue_list.get_child(i).get_theme_color("font_color")
	_check(hit >= 0, "an edit that breaks a rule shows up in the list")
	_check(err_color != waived_color, "...in another colour than a waived issue")
	_check(not screen.issue_text(issues[hit]).begins_with("UI_DEV"), "...with a translated message")
	screen.issue_list.get_child(hit).pressed.emit()
	_check(screen.floor_y == 1, "clicking an issue shows its floor")
	_check(
		screen.view.has_highlight and screen.view.highlight_tile == issues[hit]["tile"],
		"...and highlights its tile"
	)
	var centre: Vector2 = screen.view.tile_center(issues[hit]["tile"])
	_check(centre.distance_to(screen.view.size * 0.5) < 1.5, "...centred in the view")
	_check(
		screen.view._issue_marks.get(issues[hit]["tile"], "") == "error", "the map marks the tile"
	)
	_check(screen.view._issue_marks.values().has("waived"), "...and marks waived issues apart")
	# Live validation re-runs after an edit.
	screen.live_validation.button_pressed = true
	m.undo()
	_check(not screen._validate_timer.is_stopped(), "an edit schedules a validation")

	# Saving, and leaving.
	var left_count := [0]
	screen.left.connect(func(): left_count[0] += 1)
	_check(m.dirty, "(there are unsaved changes)")
	screen.request_back()
	_check(
		left_count[0] == 0 and screen._leave_dialog.visible, "Back with unsaved changes asks first"
	)
	screen._leave_dialog.hide()
	_key(screen, KEY_S, true)
	_check(
		not m.dirty and FileAccess.file_exists(TEMP + "norgzevod_frozen_lake/floor_0.map"),
		"Ctrl+S saves (into the temporary root)"
	)
	_check(
		not screen.title_label.text.contains(
			TranslationServer.translate("UI_DEV_EDITOR_DIRTY").strip_edges()
		),
		"...and the dirty mark goes"
	)
	screen.request_back()
	_check(left_count[0] == 1, "Back with nothing unsaved leaves at once")
	m.paint([Vector3i(0, 0, 0)], &"wall")
	screen.request_back()
	screen._leave_dialog.confirmed.emit()
	_check(left_count[0] == 2 and m.dirty, "discarding leaves, changes unsaved")
	screen.request_back()
	screen._on_leave_action("save")
	_check(left_count[0] == 3 and not m.dirty, "save and leave saves, then leaves")
	screen.queue_free()
	await get_tree().process_frame


func _check_gui_edge_cases() -> void:
	print("-- the screen on a partial, a missing and a huge dungeon")
	# Partial: one floor numbered 3, with a line the parser cannot read.
	DirAccess.make_dir_recursive_absolute(TEMP + "partial2")
	var f := FileAccess.open(TEMP + "partial2/floor_3.map", FileAccess.WRITE)
	f.store_string("[floor]\ny = 3\n[grid]\n.E#\n[tiles]\nZZ99 bogus_kind\n")
	f.close()
	var m := Model.new()
	m.load_dungeon(&"partial2", TEMP)
	var screen := SCREEN.instantiate()
	screen.model = m
	screen.navigate = false
	add_child(screen)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(screen.floor_y == 3, "a dungeon whose only floor is 3 opens on it")
	_check(not screen.issues.is_empty(), "the parser's problems are listed")
	_check(screen.status_label.text != "", "...and the status line says so")
	_check(screen._floor_bar.get_node_or_null("Floor_3") != null, "one floor button")
	screen.queue_free()
	# Missing.
	var gone := Model.new()
	gone.load_dungeon(&"nothing_here_at_all", TEMP)
	var screen2 := SCREEN.instantiate()
	screen2.model = gone
	screen2.navigate = false
	add_child(screen2)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(
		screen2.floor_y == 0 and not screen2.issues.is_empty(),
		"a missing dungeon opens as an empty floor with its problem listed"
	)
	screen2.select_tool("terrain:floor")
	_click(screen2, Vector3i(2, 0, 2))
	_check(gone.plan.floor_tiles.has(Vector3i(2, 0, 2)), "...and can be painted")
	screen2.queue_free()
	# A new dungeon through the launch statics.
	var Launch := preload("res://scripts/dungeon/editor/dungeon_editor_launch.gd")
	Launch.new_dungeon(&"launched_new")
	var screen3 := SCREEN.instantiate()
	screen3.navigate = false
	add_child(screen3)
	await get_tree().process_frame
	_check(
		screen3.model.slug == &"launched_new" and screen3.model.floors == [0],
		"the launch statics open a new dungeon"
	)
	_check(screen3.model.plan.floor_tiles.is_empty(), "...empty")
	Launch.edit(LAKE)
	screen3.queue_free()
	var screen4 := SCREEN.instantiate()
	screen4.navigate = false
	add_child(screen4)
	await get_tree().process_frame
	_check(
		screen4.model.slug == LAKE and screen4.model.floors.size() == 5, "...and an existing one"
	)
	screen4.queue_free()
	# No size limit: nothing is allocated per tile, only what is in view is drawn.
	var big := Model.new()
	big.new_dungeon(&"huge", TEMP)
	big.paint([Vector3i(0, 0, 0), Vector3i(1000000, 0, 1000000)], &"floor")
	big.place(&"chest", Vector3i(1000000, 0, 1000000))
	var screen5 := SCREEN.instantiate()
	screen5.model = big
	screen5.navigate = false
	add_child(screen5)
	await get_tree().process_frame
	await get_tree().process_frame
	var t0 := Time.get_ticks_msec()
	screen5.view.queue_redraw()
	await get_tree().process_frame
	var seen: Rect2i = screen5.view.visible_range()
	_check(seen.size.x * seen.size.y < 200000, "a huge map shows only the tiles in view")
	screen5.view.center_on(Vector3i(1000000, 0, 1000000))
	var near: Rect2i = screen5.view.visible_range()
	_check(near.has_point(Vector2i(1000000, 1000000)), "...and can be scrolled to its far corner")
	await get_tree().process_frame
	_check(Time.get_ticks_msec() - t0 < 5000, "...in no time")
	screen5.queue_free()
	await get_tree().process_frame


# --------------------------------------------------------------------------
# Translations
# --------------------------------------------------------------------------


## The msgid -> msgstr pairs of a .po file.
func _po(path: String) -> Dictionary:
	var out := {}
	var key := ""
	for line in FileAccess.get_file_as_string(path).split("\n"):
		if line.begins_with('msgid "'):
			key = line.substr(7, line.length() - 8)
		elif line.begins_with('msgstr "') and key != "":
			out[key] = line.substr(8, line.length() - 9)
			key = ""
	return out


func _check_translations() -> void:
	print("-- every sentence of the editor is translated, both ways")
	var en := _po("res://translations/en.po")
	var fr := _po("res://translations/fr.po")
	var keys: Array[String] = []
	var sources := ""
	for path in [
		"res://scripts/dungeon/editor/dungeon_editor_screen.gd",
		"res://scripts/dungeon/editor/dungeon_prop_form.gd",
		"res://scripts/dungeon/editor/dungeon_editor_view.gd",
		"res://scripts/dungeon/editor/dungeon_editor_texts.gd",
		"res://scripts/dungeon/editor/dungeon_editor_layout.gd",
		"res://scripts/dungeon/editor/dungeon_editor_palette.gd",
		"res://scripts/dungeon/editor/dungeon_zone_panel.gd",
		"res://scripts/dev/scenario_select.gd",
	]:
		sources += FileAccess.get_file_as_string(path)
	var re := RegEx.new()
	re.compile('"(UI_DEV_(?:EDITOR|DUNGEON)_[A-Z_]*[A-Z])"')
	for hit in re.search_all(sources):
		keys.append(hit.get_string(1))
	for terrain in Model.TERRAINS:
		keys.append("UI_DEV_EDITOR_TERRAIN_" + String(terrain).to_upper())
	for kind in Kinds.KINDS:
		keys.append("UI_DEV_EDITOR_KIND_" + String(kind).to_upper())
	for tool in [
		"SELECT", "ERASE", "ENTRANCE", "EXIT", "EXIT_REMOVE", "ZONE_PAINT", "ZONE_ERASE", "EMERGE"
	]:
		keys.append("UI_DEV_EDITOR_TOOL_" + tool)
		keys.append("UI_DEV_EDITOR_HINT_" + tool)
	for hint in ["TERRAIN", "KIND", "STAIRS"]:
		keys.append("UI_DEV_EDITOR_HINT_" + hint)
	for code in Validator.MESSAGES:
		keys.append("UI_DEV_ISSUE_" + code)
	var model_source := FileAccess.get_file_as_string(
		"res://scripts/dungeon/editor/dungeon_editor_model.gd"
	)
	for piece in model_source.split('_refuse("').slice(1):
		var code: String = piece.get_slice('"', 0)
		if code != "" and not code.contains(":"):
			keys.append("UI_DEV_EDITOR_ERR_" + code)
	var missing: Array[String] = []
	var untranslated: Array[String] = []
	var shape: Array[String] = []
	for key in keys:
		if not en.has(key) or not fr.has(key) or en[key] == "" or fr[key] == "":
			missing.append(key)
			continue
		if en[key] == fr[key] and en[key].length() > 12:
			untranslated.append(key)
		for token in ["%s", "%d"]:
			if en[key].count(token) != fr[key].count(token):
				shape.append(key)
	_check(missing.is_empty(), "no key is missing from en.po or fr.po: %s" % [missing])
	_check(untranslated.is_empty(), "no long French line is the English one: %s" % [untranslated])
	_check(shape.is_empty(), "French keeps the English placeholders: %s" % [shape])
	_check(keys.size() > 150, "(%d keys checked)" % keys.size())
	# The project's vocabulary: "tile" is a case, a round or a turn is a tour, a species a variété.
	var bad: Array[String] = []
	for key in fr:
		if key.begins_with("UI_DEV_EDITOR_") or key.begins_with("UI_DEV_ISSUE_"):
			var low: String = fr[key].to_lower()
			for word in ["battle", "fighter", "ronde", "espèce", "combat", "cellule"]:
				if low.contains(word):
					bad.append("%s (%s)" % [key, word])
	for key in en:
		if key.begins_with("UI_DEV_EDITOR_") or key.begins_with("UI_DEV_ISSUE_"):
			var low: String = en[key].to_lower()
			for word in ["battle", "fighter", " cell ", "cells"]:
				if low.contains(word):
					bad.append("%s (%s)" % [key, word])
	_check(bad.is_empty(), "the project's vocabulary is respected: %s" % [bad])
	# An editor key nothing asks for is dead weight.
	var dead: Array[String] = []
	for key in en:
		if not key.begins_with("UI_DEV_EDITOR_"):
			continue
		var used := sources.contains('"%s"' % key)
		for prefix in [
			"UI_DEV_EDITOR_TERRAIN_",
			"UI_DEV_EDITOR_KIND_",
			"UI_DEV_EDITOR_TOOL_",
			"UI_DEV_EDITOR_HINT_",
			"UI_DEV_EDITOR_ERR_"
		]:
			if key.begins_with(prefix) and sources.contains('"%s"' % prefix):
				used = true
		if not used:
			dead.append(key)
	_check(dead.is_empty(), "every editor key is used: %s" % [dead])


func _clean_temp() -> void:
	_remove_dir(TEMP)


func _remove_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_remove_dir(path.path_join(sub))
	for f in dir.get_files():
		dir.remove(f)
	DirAccess.remove_absolute(path)
