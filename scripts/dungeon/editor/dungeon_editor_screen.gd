## The dungeon editor's screen: the palette on the left, the map in the middle, the inspector and
## the issues on the right. A DEV tool, reached from the Dungeons tab of the scenario picker and
## from nowhere else.
##
## Thin on purpose: every change goes through [method model] (the model is where undo, validation
## and saving live, and where the checks reach it), the map is [DungeonEditorView], and the form
## of properties is built from the kinds table by [DungeonPropForm]. What is left here is the glue:
## tools, selection, the keyboard, and the dialogs.
##
## Every sentence goes through a translation key. The names of kinds, properties, enum values and
## tags are the format's own identifiers and are shown as the files spell them.
##
## No `class_name` (the CLI class-cache trap): referenced by `preload`.
extends Control

## Emitted when the screen wants to be left (the Back button, once unsaved changes are settled).
signal left

const Kinds := preload("res://scripts/dungeon/dungeon_kinds.gd")
const Writer := preload("res://scripts/dungeon/dungeon_map_writer.gd")
const Validator := preload("res://scripts/dungeon/dungeon_validator.gd")
const Model := preload("res://scripts/dungeon/editor/dungeon_editor_model.gd")
const Util := preload("res://scripts/dungeon/editor/dungeon_editor_util.gd")
const View := preload("res://scripts/dungeon/editor/dungeon_editor_view.gd")
const Form := preload("res://scripts/dungeon/editor/dungeon_prop_form.gd")
const Launch := preload("res://scripts/dungeon/editor/dungeon_editor_launch.gd")
const Texts := preload("res://scripts/dungeon/editor/dungeon_editor_texts.gd")
const Layout := preload("res://scripts/dungeon/editor/dungeon_editor_layout.gd")
const ZonePanel := preload("res://scripts/dungeon/editor/dungeon_zone_panel.gd")

const SCENARIO_SELECT := "res://scenes/dev/scenario_select.tscn"
const DIRS: Array[String] = ["N", "E", "S", "W"]
## How long after an edit the validator runs again.
const VALIDATE_DELAY := 0.6
const DIM := Color(0.68, 0.70, 0.76)

## The model the screen edits. Set it before adding the screen to the tree to open something
## other than what [DungeonEditorLaunch] says (the checks and the screenshot do).
var model: Model
## False in a check: leaving then only emits [signal left] and changes no scene.
var navigate := true

var view: View
var tool := "select"
var floor_y := 0
var issues: Array = []
## One flat button per issue; pressing one jumps to its tile.
var issue_list: VBoxContainer
var status_label: Label
var hover_label: Label
var title_label: Label
var save_button: Button
var undo_button: Button
var redo_button: Button
var live_validation: CheckBox

var _tool_buttons: Dictionary = {}
var _tool_box: VBoxContainer
var _sel_box: VBoxContainer
var _floor_bar: HBoxContainer
var _floor_list: Array[int] = []
var _issues_header: Label
var _leave_dialog: ConfirmationDialog
var _floor_dialog: ConfirmationDialog
var _sel_tile := Vector3i.ZERO
var _has_sel := false
var _sel_uid := -1
var _templates: Dictionary = {}  # kind -> props of the next placement
var _entrance_facing := "N"
var _entrance_edge := ""
var _exit_edge := ""
var _stairs_partner := true
var _zone := ""
var _pick: Dictionary = {}
var _rect_start = null
var _stroking := false
var _stroke_open := false
var _validate_timer: Timer
var _quiet := 0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if model == null:
		model = Model.new()
		if Launch.create:
			model.new_dungeon(Launch.slug)
		else:
			model.load_dungeon(Launch.slug)
	floor_y = model.floors[0] if not model.floors.has(0) else 0
	Layout.build(self)
	model.changed.connect(_on_model_changed)
	view.bind(model)
	view.floor_y = floor_y
	_refresh_all()
	validate()
	if not model.load_issues.is_empty():
		_say(_t("UI_DEV_EDITOR_LOAD_ISSUES") % model.load_issues.size())
	await get_tree().process_frame
	view.fit()


# --------------------------------------------------------------------------
# Building the screen
# --------------------------------------------------------------------------

# --------------------------------------------------------------------------
# Public operations (the buttons, the keys and the checks all go through these)
# --------------------------------------------------------------------------


func select_tool(id: String) -> void:
	if not _tool_buttons.has(id):
		return
	tool = id
	_tool_buttons[id].button_pressed = true
	_pick = {}
	view.picking = false
	_rebuild_tool_box()
	_say(_hint())


func set_floor(y: int) -> void:
	if not model.floors.has(y):
		return
	floor_y = y
	view.floor_y = y
	if _has_sel and _sel_tile.y != y:
		deselect()
	_refresh_floor_bar()
	view.queue_redraw()


func undo() -> void:
	model.undo()


func redo() -> void:
	model.redo()


func save() -> Error:
	var err := model.save()
	if err == OK:
		var names := ", ".join(PackedStringArray(model.last_written))
		_say(
			(
				_t("UI_DEV_EDITOR_SAVED") % names
				if not model.last_written.is_empty()
				else _t("UI_DEV_EDITOR_NOTHING_TO_SAVE")
			)
		)
	else:
		_say(_t("UI_DEV_EDITOR_SAVE_FAILED") % err)
	_update_chrome()
	return err


## Back to the scenario picker, after asking what to do with unsaved changes.
func request_back() -> void:
	if model.dirty:
		_leave_dialog.popup_centered()
	else:
		_leave()


func _on_leave_action(action: String) -> void:
	if action == "save" and save() == OK:
		_leave_dialog.hide()
		_leave()


func _leave() -> void:
	left.emit()
	if navigate:
		TransitionManager.change_scene(SCENARIO_SELECT)


func validate() -> Array:
	issues = model.validate()
	view.set_issues(issues)
	_fill_issues()
	return issues


## Shows an issue: its floor, its tile centred and highlighted.
func jump_to_issue(index: int) -> void:
	if index < 0 or index >= issues.size():
		return
	var tile = issues[index]["tile"]
	if tile == null:
		return
	if model.floors.has(tile.y):
		set_floor(tile.y)
	view.highlight_tile = tile
	view.has_highlight = true
	view.center_on(tile)
	view.queue_redraw()


func deselect() -> void:
	_has_sel = false
	_sel_uid = -1
	view.has_selection = false
	view.selected_uid = -1
	view.has_highlight = false
	view.queue_redraw()
	_rebuild_selection_box()


func select_tile(tile: Vector3i, uid: int = -1) -> void:
	_has_sel = true
	_sel_tile = tile
	var here: Array = model.placements_at(tile)
	if uid >= 0:
		_sel_uid = uid
	elif not here.is_empty():
		_sel_uid = here[0]["uid"]
	else:
		_sel_uid = -1
	view.selected_tile = tile
	view.has_selection = true
	view.selected_uid = _sel_uid
	view.queue_redraw()
	_rebuild_selection_box()


func add_floor_above() -> void:
	if model.add_floor(model.floors[-1] + 1):
		set_floor(model.floors[-1])


func add_floor_below() -> void:
	if model.add_floor(model.floors[0] - 1):
		set_floor(model.floors[0])


func _delete_current_floor() -> void:
	var gone := floor_y
	if not model.delete_floor(gone):
		_say(_refusal())
		return
	set_floor(model.floors[-1] if gone > model.floors[-1] else _nearest_floor(gone))


func _nearest_floor(y: int) -> int:
	var best: int = model.floors[0]
	for f in model.floors:
		if absi(f - y) < absi(best - y):
			best = f
	return best


# --------------------------------------------------------------------------
# Keys
# --------------------------------------------------------------------------


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var ctrl: bool = event.ctrl_pressed or event.meta_pressed
	match event.keycode:
		KEY_Z:
			if ctrl:
				if event.shift_pressed:
					redo()
				else:
					undo()
				get_viewport().set_input_as_handled()
		KEY_Y:
			if ctrl:
				redo()
				get_viewport().set_input_as_handled()
		KEY_S:
			if ctrl:
				save()
				get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			if not _pick.is_empty():
				_end_pick()
			else:
				deselect()
			get_viewport().set_input_as_handled()
		KEY_DELETE, KEY_BACKSPACE:
			if _sel_uid >= 0:
				_remove_selected(false)
				get_viewport().set_input_as_handled()
		_:
			if event.keycode >= KEY_1 and event.keycode <= KEY_9 and not ctrl:
				var index: int = event.keycode - KEY_1
				if index < model.floors.size():
					set_floor(model.floors[index])
					get_viewport().set_input_as_handled()


# --------------------------------------------------------------------------
# The mouse on the map
# --------------------------------------------------------------------------


func _on_stroke_began(tile: Vector3i, shift: bool) -> void:
	if not _pick.is_empty():
		_deliver_pick(tile)
		return
	_stroking = true
	match _tool_kind():
		"terrain", "zone_paint", "zone_erase":
			if shift:
				_rect_start = tile
				view.rect_from = tile
				view.rect_to = tile
			else:
				model.begin("stroke")
				_stroke_open = true
				_stroke_tile(tile)
		"erase":
			model.begin("erase")
			_stroke_open = true
			_erase_at(tile)
		"select":
			_click_select(tile)
		"entrance":
			model.set_entrance(tile, _entrance_facing, _entrance_edge)
			_after_op(_t("UI_DEV_EDITOR_ENTRANCE_SET") % Writer.cell_name(tile.x, tile.z))
		"exit":
			model.add_exit(tile, _exit_edge)
			_after_op("")
		"exit_remove":
			model.remove_exit(tile)
			_after_op("")
		"kind":
			_place_kind(tile)
		"emerge":
			model.set_emerge(tile)
			_after_op(_t("UI_DEV_EDITOR_EMERGE_SET") % Writer.cell_name(tile.x, tile.z))
			_rebuild_tool_box()


func _on_stroke_moved(tile: Vector3i) -> void:
	if _rect_start != null:
		view.rect_to = tile
		view.queue_redraw()
		return
	if not _stroking:
		return
	match _tool_kind():
		"terrain", "zone_paint", "zone_erase":
			_stroke_tile(tile)
		"erase":
			_erase_at(tile)


func _on_stroke_ended(tile: Vector3i) -> void:
	if not _stroking:
		return
	_stroking = false
	if _rect_start != null:
		var a: Vector3i = _rect_start
		_rect_start = null
		view.rect_from = null
		view.rect_to = null
		var tiles := Util.rect_tiles(a, tile)
		match _tool_kind():
			"terrain":
				model.paint(tiles, StringName(tool.get_slice(":", 1)))
			"zone_paint":
				model.zone_paint(_zone, tiles)
			"zone_erase":
				model.zone_erase(_zone, tiles)
		_after_op("")
		return
	if _stroke_open:
		_stroke_open = false
		model.commit()
	view.queue_redraw()


func _on_secondary(tile: Vector3i) -> void:
	select_tile(tile)


func _on_hovered(tile: Vector3i, inside: bool) -> void:
	hover_label.text = describe(tile) if inside else ""


func _stroke_tile(tile: Vector3i) -> void:
	match _tool_kind():
		"terrain":
			model.paint([tile], StringName(tool.get_slice(":", 1)))
		"zone_paint":
			model.zone_paint(_zone, [tile])
		"zone_erase":
			model.zone_erase(_zone, [tile])
	view.queue_redraw()


func _erase_at(tile: Vector3i) -> void:
	var here: Array = model.placements_at(tile)
	if not here.is_empty():
		model.remove_placement(here[-1]["uid"])
	elif model.plan.exits.has(tile):
		model.remove_exit(tile)
	view.queue_redraw()


func _click_select(tile: Vector3i) -> void:
	var here: Array = model.placements_at(tile)
	if _has_sel and _sel_tile == tile and here.size() > 1:
		# A second click on the same tile walks through what is stacked on it.
		var index := 0
		for i in here.size():
			if here[i]["uid"] == _sel_uid:
				index = (i + 1) % here.size()
		select_tile(tile, here[index]["uid"])
	else:
		select_tile(tile)


func _place_kind(tile: Vector3i) -> void:
	var kind := StringName(tool.get_slice(":", 1))
	var props: Dictionary = _template(kind)
	var uid := -1
	var note := ""
	if kind == &"stairs":
		var face := Writer.dir_letter(props.get("face", Kinds.DIRECTIONS["N"]))
		uid = model.place_stairs(tile, props.get("dir", "up"), face, _stairs_partner)
		if uid >= 0 and _stairs_partner:
			var sp: Dictionary = model.stairs_partner(tile, model.placement(uid)["props"])
			if model.last_partner_uid >= 0:
				note = _t("UI_DEV_EDITOR_PARTNER_PLACED") % sp["tile"].y
			elif not sp.is_empty():
				note = ""
			else:
				var wanted: int = tile.y + (1 if props.get("dir", "up") == "up" else -1)
				note = _t("UI_DEV_EDITOR_PARTNER_MISSING") % wanted
	else:
		uid = model.place(kind, tile, props)
	if uid < 0:
		_say(_refusal())
		return
	select_tile(tile, uid)
	_say(note)


func _after_op(message: String) -> void:
	view.queue_redraw()
	if model.last_error != "" and message == "":
		_say(_refusal())
	elif message != "":
		_say(message)


func _tool_kind() -> String:
	return tool.get_slice(":", 0)


# --------------------------------------------------------------------------
# Picking a tile on the map for a property
# --------------------------------------------------------------------------


func _start_pick(name: String, type: String) -> void:
	if _pick.get("name", "") == name:
		_end_pick()
		return
	_pick = {"name": name, "type": type}
	view.picking = true
	_say(_t("UI_DEV_EDITOR_PICKING") % name)
	_rebuild_selection_box()


func _end_pick() -> void:
	_pick = {}
	view.picking = false
	_say("")
	_rebuild_selection_box()


func _deliver_pick(tile: Vector3i) -> void:
	var name: String = _pick["name"]
	var props: Dictionary = _form_props()
	if _pick["type"] == "tiles":
		var list: Array = props.get(name, []).duplicate()
		list.append(tile)
		props[name] = list
	else:
		props[name] = tile
	_apply_form(props, true)
	if _pick["type"] == "tile":
		_end_pick()


# --------------------------------------------------------------------------
# The inspector
# --------------------------------------------------------------------------


func _rebuild_tool_box() -> void:
	_clear(_tool_box)
	var kind := _tool_kind()
	_tool_box.add_child(_heading(_tool_title()))
	_tool_box.add_child(_wrapped(_hint()))
	match kind:
		"entrance":
			_tool_box.add_child(_dir_row("UI_DEV_EDITOR_FACING", _entrance_facing, "facing"))
			_tool_box.add_child(_dir_row("UI_DEV_EDITOR_EXIT_EDGE", _entrance_edge, "edge"))
		"exit":
			_tool_box.add_child(_dir_row("UI_DEV_EDITOR_EXIT_EDGE", _exit_edge, "exit"))
		"kind":
			var k := StringName(tool.get_slice(":", 1))
			if k == &"stairs":
				_tool_box.add_child(_partner_check())
			var holder := VBoxContainer.new()
			holder.name = "TemplateForm"
			_tool_box.add_child(holder)
			Form.build(
				holder,
				k,
				func(): return _template(k),
				floor_y,
				_edit_template,
				_start_pick,
				_pick.get("name", "")
			)
		"zone_paint", "zone_erase":
			_build_zone_controls()
		"emerge":
			var tile = model.emerge_tile()
			var text: String = (
				_t("UI_DEV_EDITOR_EMERGE_NONE") if tile == null else Writer.tile_ref(tile, 0)
			)
			_tool_box.add_child(_wrapped(_t("UI_DEV_EDITOR_EMERGE_CURRENT") % text))


func _tool_title() -> String:
	var kind := _tool_kind()
	var id := tool.get_slice(":", 1)
	match kind:
		"terrain":
			return _t("UI_DEV_EDITOR_TERRAIN_" + id.to_upper())
		"kind":
			return kind_label(StringName(id))
	return _t("UI_DEV_EDITOR_TOOL_" + kind.to_upper())


func _hint() -> String:
	var key := "UI_DEV_EDITOR_HINT_" + _tool_kind().to_upper()
	if _tool_kind() == "kind" and tool.get_slice(":", 1) == "stairs":
		key = "UI_DEV_EDITOR_HINT_STAIRS"
	return _t(key)


func _template(kind: StringName) -> Dictionary:
	if not _templates.has(kind):
		_templates[kind] = (
			{"dir": "up", "face": Kinds.DIRECTIONS["N"]} if kind == &"stairs" else {}
		)
	return _templates[kind]


func _edit_template(next: Dictionary, structural: bool) -> void:
	_templates[StringName(tool.get_slice(":", 1))] = next
	if structural:
		_rebuild_tool_box.call_deferred()


func _partner_check() -> CheckBox:
	var c := Layout.checkbox(
		"UI_DEV_EDITOR_STAIRS_PARTNER", _stairs_partner, func(on): _stairs_partner = on
	)
	c.name = "PartnerCheck"
	return c


func _dir_row(label_key: String, current: String, which: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	var label := Label.new()
	label.text = _t(label_key)
	label.custom_minimum_size = Vector2(96, 0)
	label.add_theme_font_size_override("font_size", 12)
	row.add_child(label)
	var group := ButtonGroup.new()
	group.allow_unpress = true
	for letter in DIRS:
		var b := Button.new()
		b.text = letter
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(28, 0)
		b.button_pressed = current == letter
		b.pressed.connect(_set_dir_option.bind(which, letter, b))
		row.add_child(b)
	return row


func _set_dir_option(which: String, letter: String, button: Button) -> void:
	var value := letter if button.button_pressed else ""
	match which:
		"facing":
			_entrance_facing = value
		"edge":
			_entrance_edge = value
		"exit":
			_exit_edge = value


func create_zone(name: String) -> void:
	if model.create_zone(name):
		_zone = name
		_say("")
		_rebuild_tool_box()
	else:
		_say(_refusal())


func delete_zone() -> void:
	if _zone != "" and model.delete_zone(_zone):
		_zone = ""
		_rebuild_tool_box()


func _set_zone_tags(text: String) -> void:
	if _zone == "":
		return
	var tags: Array[String] = []
	for part in text.split(",", false):
		tags.append(part.strip_edges())
	if ",".join(tags) != ",".join(PackedStringArray(model.plan.zones[_zone]["tags"])):
		_quiet += 1
		model.set_zone_tags(_zone, tags)
		_quiet -= 1


func _set_zone_note(text: String) -> void:
	if _zone == "" or text == model.plan.zones[_zone]["props"].get("note", ""):
		return
	_quiet += 1
	if not model.set_zone_prop(_zone, "note", text.strip_edges()):
		_say(_refusal())
	_quiet -= 1


func _rebuild_selection_box() -> void:
	_clear(_sel_box)
	if not _has_sel:
		_sel_box.add_child(_wrapped(_t("UI_DEV_EDITOR_NOTHING_SELECTED"), true))
		return
	var tile := _sel_tile
	var cell := Writer.cell_name(tile.x, tile.z)
	_sel_box.add_child(
		_heading(_t("UI_DEV_EDITOR_TILE") % [cell, tile.y, _terrain_name(model.terrain_of(tile))])
	)
	var here: Array = model.placements_at(tile)
	if not here.is_empty():
		var list := HFlowContainer.new()
		list.name = "PlacementList"
		for p in here:
			var b := Button.new()
			b.text = kind_label(p["kind"])
			b.tooltip_text = String(p["kind"])
			b.toggle_mode = true
			b.button_pressed = p["uid"] == _sel_uid
			b.focus_mode = Control.FOCUS_NONE
			b.pressed.connect(select_tile.bind(tile, p["uid"]))
			list.add_child(b)
		_sel_box.add_child(list)
	var holder := VBoxContainer.new()
	holder.name = "SelectionForm"
	holder.add_theme_constant_override("separation", 3)
	_sel_box.add_child(holder)
	if _sel_uid >= 0 and not model.placement(_sel_uid).is_empty():
		var p: Dictionary = model.placement(_sel_uid)
		holder.add_child(_heading("%s (%s)" % [kind_label(p["kind"]), p["kind"]]))
		Form.build(
			holder, p["kind"], _form_props, tile.y, _apply_form, _start_pick, _pick.get("name", "")
		)
		var buttons := HBoxContainer.new()
		buttons.add_child(_button("UI_DEV_EDITOR_REMOVE", _remove_selected.bind(false)))
		if p["kind"] == &"stairs":
			buttons.add_child(_button("UI_DEV_EDITOR_REMOVE_BOTH", _remove_selected.bind(true)))
		holder.add_child(buttons)
	else:
		holder.add_child(_heading(_t("UI_DEV_EDITOR_TILE_PROPS")))
		Form.build(
			holder, &"", _form_props, tile.y, _apply_form, _start_pick, _pick.get("name", "")
		)
	var zones := model.zones_at(tile)
	if not zones.is_empty():
		_sel_box.add_child(_wrapped(_t("UI_DEV_EDITOR_ZONES_HERE") % ", ".join(zones)))


## The properties the form edits: the selected placement's, the tile's own, or (while a
## placement tool is active and nothing is selected) the next placement's.
func _form_props() -> Dictionary:
	if _sel_uid >= 0 and not model.placement(_sel_uid).is_empty():
		return model.placement(_sel_uid)["props"].duplicate(true)
	if _has_sel:
		return model.tile_props(_sel_tile)
	return {}


## Applies edited properties from the form to what it shows.
func _apply_form(next: Dictionary, structural: bool) -> void:
	_quiet += 1
	var ok := true
	if _sel_uid >= 0 and not model.placement(_sel_uid).is_empty():
		ok = model.edit_placement(_sel_uid, next)
	elif _has_sel:
		ok = _apply_tile_props(next)
	_quiet -= 1
	if not ok:
		_say(_refusal())
	if structural or not ok:
		_rebuild_selection_box.call_deferred()


## Makes the tile's own properties `next`, one command.
func _apply_tile_props(next: Dictionary) -> bool:
	var before := model.tile_props(_sel_tile)
	model.begin("tile")
	var ok := true
	for name in before:
		if not next.has(name):
			ok = model.set_tile_prop(_sel_tile, name, null) and ok
	for name in next:
		if before.get(name) != next[name]:
			ok = model.set_tile_prop(_sel_tile, name, next[name]) and ok
	model.commit()
	return ok


func _remove_selected(with_partner: bool) -> void:
	if _sel_uid < 0:
		return
	if model.remove_placement(_sel_uid, with_partner):
		_sel_uid = -1
		view.selected_uid = -1
		_rebuild_selection_box()
	else:
		_say(_refusal())


func _clear(box: Control) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _wrapped(text: String, dim: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(300, 0)
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", DIM if dim else Color(0.85, 0.87, 0.9))
	return l


# --------------------------------------------------------------------------
# Issues, hover, chrome
# --------------------------------------------------------------------------


func _fill_issues() -> void:
	_clear(issue_list)
	var errors := Validator.error_count(issues)
	_issues_header.text = _t("UI_DEV_EDITOR_ISSUES") % [errors, issues.size() - errors]
	if issues.is_empty():
		issue_list.add_child(_wrapped(_t("UI_DEV_EDITOR_ISSUES_NONE"), true))
		return
	for i in issues.size():
		var b := Texts.issue_button(issues[i])
		b.pressed.connect(jump_to_issue.bind(i))
		issue_list.add_child(b)


func _refresh_all() -> void:
	_refresh_floor_bar()
	_rebuild_tool_box()
	_rebuild_selection_box()
	_update_chrome()


func _refresh_floor_bar() -> void:
	if _floor_list != model.floors:
		_floor_list = model.floors.duplicate()
		_clear(_floor_bar)
		var group := ButtonGroup.new()
		for y in _floor_list:
			var b := Button.new()
			b.text = _t("UI_DEV_EDITOR_FLOOR") % y
			b.toggle_mode = true
			b.button_group = group
			b.focus_mode = Control.FOCUS_NONE
			b.name = "Floor_%d" % y
			b.pressed.connect(set_floor.bind(y))
			_floor_bar.add_child(b)
	if not model.floors.has(floor_y):
		floor_y = _nearest_floor(floor_y)
		view.floor_y = floor_y
	for y in _floor_list:
		var b: Button = _floor_bar.get_node_or_null("Floor_%d" % y)
		if b != null:
			b.button_pressed = y == floor_y


func _ask_delete_floor() -> void:
	_floor_dialog.dialog_text = _t("UI_DEV_EDITOR_FLOOR_DELETE_TEXT") % floor_y
	_floor_dialog.popup_centered()


func _update_chrome() -> void:
	var mark := _t("UI_DEV_EDITOR_DIRTY") if model.dirty else ""
	title_label.text = _t("UI_DEV_EDITOR_TITLE") % [model.title, model.slug] + mark
	undo_button.disabled = not model.can_undo()
	redo_button.disabled = not model.can_redo()
	save_button.text = _t("UI_DEV_EDITOR_SAVE") + (" *" if model.dirty else "")


func _on_model_changed() -> void:
	_update_chrome()
	_refresh_floor_bar()
	if _sel_uid >= 0 and model.placement(_sel_uid).is_empty():
		_sel_uid = -1
		view.selected_uid = -1
	if _quiet == 0:
		_rebuild_selection_box()
		if _tool_kind() in ["zone_paint", "zone_erase", "emerge"]:
			_rebuild_tool_box()
	if live_validation != null and live_validation.button_pressed:
		_validate_timer.start()
	else:
		view.clear_issues()
	view.queue_redraw()


func _set_view(what: String, on: bool) -> void:
	match what:
		"below":
			view.show_below = on
		"zones":
			view.show_zones = on
		"grid":
			view.show_grid = on
	view.queue_redraw()


func _say(text: String) -> void:
	if status_label != null:
		status_label.text = text


func _build_zone_controls() -> void:
	var names: Array = model.plan.zones.keys()
	names.sort()
	if _zone == "" or not model.plan.zones.has(_zone):
		_zone = String(names[0]) if not names.is_empty() else ""
	view.zone_name = _zone
	var handlers := {
		"pick": _pick_zone,
		"create": create_zone,
		"tags": _set_zone_tags,
		"note": _set_zone_note,
		"delete": delete_zone,
	}
	ZonePanel.build(_tool_box, model.plan.zones, _zone, handlers)


func _pick_zone(name: String) -> void:
	_zone = name
	view.zone_name = _zone
	view.queue_redraw()
	_rebuild_tool_box()


## The translated line for an issue.
func issue_text(issue: Dictionary) -> String:
	return Texts.issue_text(issue)


## What the hover line says about a tile.
func describe(tile: Vector3i) -> String:
	return Texts.describe(model, tile)


func _refusal() -> String:
	return Texts.refusal(model.last_error)


func _terrain_name(terrain: StringName) -> String:
	return Texts.terrain_name(terrain)


## A kind's translated name, or its identifier while it has none.
static func kind_label(kind: StringName) -> String:
	return Texts.kind_label(kind)


static func _t(key: String) -> String:
	return Texts.t(key)


func _button(key: String, on_press: Callable) -> Button:
	return Layout.button(key, on_press)
