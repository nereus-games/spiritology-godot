## The layout of the dungeon editor's screen: the bars, the palette, the map, the inspector and the
## issues list, built in code like the rest of the dev screens. It only builds: the widgets it
## creates are handed to the screen's fields, and every button is wired to a method of the screen.
##
## No `class_name` (the CLI class-cache trap): referenced by `preload`.
extends RefCounted

const View := preload("res://scripts/dungeon/editor/dungeon_editor_view.gd")
const Texts := preload("res://scripts/dungeon/editor/dungeon_editor_texts.gd")
const Palette := preload("res://scripts/dungeon/editor/dungeon_editor_palette.gd")


static func build(screen: Control) -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 8)
	screen.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	margin.add_child(root)
	root.add_child(_top_bar(screen))
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	root.add_child(body)
	body.add_child(Palette.build(screen._tool_buttons, screen.select_tool))
	body.add_child(_center(screen))
	body.add_child(_right(screen))
	screen.status_label = Label.new()
	screen.status_label.add_theme_font_size_override("font_size", 12)
	screen.status_label.add_theme_color_override("font_color", Palette.DIM)
	screen.status_label.clip_text = true
	root.add_child(screen.status_label)
	screen._leave_dialog = ConfirmationDialog.new()
	screen._leave_dialog.title = Texts.t("UI_DEV_EDITOR_LEAVE_TITLE")
	screen._leave_dialog.dialog_text = Texts.t("UI_DEV_EDITOR_LEAVE_TEXT")
	screen._leave_dialog.ok_button_text = Texts.t("UI_DEV_EDITOR_LEAVE_DISCARD")
	screen._leave_dialog.cancel_button_text = Texts.t("UI_DEV_EDITOR_CANCEL")
	screen._leave_dialog.add_button(Texts.t("UI_DEV_EDITOR_LEAVE_SAVE"), true, "save")
	screen._leave_dialog.confirmed.connect(screen._leave)
	screen._leave_dialog.custom_action.connect(screen._on_leave_action)
	screen.add_child(screen._leave_dialog)
	screen._floor_dialog = ConfirmationDialog.new()
	screen._floor_dialog.title = Texts.t("UI_DEV_EDITOR_FLOOR_DELETE")
	screen._floor_dialog.ok_button_text = Texts.t("UI_DEV_EDITOR_FLOOR_DELETE")
	screen._floor_dialog.cancel_button_text = Texts.t("UI_DEV_EDITOR_CANCEL")
	screen._floor_dialog.confirmed.connect(screen._delete_current_floor)
	screen.add_child(screen._floor_dialog)
	screen._validate_timer = Timer.new()
	screen._validate_timer.one_shot = true
	screen._validate_timer.wait_time = screen.VALIDATE_DELAY
	screen._validate_timer.timeout.connect(screen.validate)
	screen.add_child(screen._validate_timer)


static func _top_bar(screen: Control) -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	var back := button("UI_DEV_EDITOR_BACK", screen.request_back)
	back.name = "BackButton"
	bar.add_child(back)
	screen.title_label = Label.new()
	screen.title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(screen.title_label)
	screen.undo_button = button("UI_DEV_EDITOR_UNDO", screen.undo)
	screen.undo_button.tooltip_text = "Ctrl+Z"
	bar.add_child(screen.undo_button)
	screen.redo_button = button("UI_DEV_EDITOR_REDO", screen.redo)
	screen.redo_button.tooltip_text = "Ctrl+Y"
	bar.add_child(screen.redo_button)
	screen.save_button = button("UI_DEV_EDITOR_SAVE", screen.save)
	screen.save_button.tooltip_text = "Ctrl+S"
	bar.add_child(screen.save_button)
	return bar


static func _center(screen: Control) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.custom_minimum_size = Vector2(300, 0)
	box.add_theme_constant_override("separation", 4)
	var bar := HFlowContainer.new()
	bar.add_theme_constant_override("h_separation", 12)
	bar.add_theme_constant_override("v_separation", 2)
	screen._floor_bar = HBoxContainer.new()
	screen._floor_bar.add_theme_constant_override("separation", 2)
	bar.add_child(screen._floor_bar)
	var ops := HBoxContainer.new()
	ops.add_theme_constant_override("separation", 2)
	ops.add_child(button("UI_DEV_EDITOR_FLOOR_ADD_ABOVE", screen.add_floor_above))
	ops.add_child(button("UI_DEV_EDITOR_FLOOR_ADD_BELOW", screen.add_floor_below))
	ops.add_child(button("UI_DEV_EDITOR_FLOOR_DELETE", screen._ask_delete_floor))
	bar.add_child(ops)
	var opts := HBoxContainer.new()
	opts.add_child(
		checkbox("UI_DEV_EDITOR_SHOW_BELOW", true, func(on): screen._set_view("below", on))
	)
	opts.add_child(
		checkbox("UI_DEV_EDITOR_SHOW_ZONES", true, func(on): screen._set_view("zones", on))
	)
	opts.add_child(
		checkbox("UI_DEV_EDITOR_SHOW_GRID", true, func(on): screen._set_view("grid", on))
	)
	opts.add_child(button("UI_DEV_EDITOR_FIT", func(): screen.view.fit()))
	bar.add_child(opts)
	box.add_child(bar)
	screen.view = View.new()
	screen.view.name = "MapView"
	screen.view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	screen.view.custom_minimum_size = Vector2(400, 300)
	screen.view.stroke_began.connect(screen._on_stroke_began)
	screen.view.stroke_moved.connect(screen._on_stroke_moved)
	screen.view.stroke_ended.connect(screen._on_stroke_ended)
	screen.view.secondary.connect(screen._on_secondary)
	screen.view.hovered.connect(screen._on_hovered)
	box.add_child(screen.view)
	screen.hover_label = Label.new()
	screen.hover_label.add_theme_font_size_override("font_size", 13)
	screen.hover_label.clip_text = true
	screen.hover_label.custom_minimum_size = Vector2(0, 20)
	box.add_child(screen.hover_label)
	return box


static func _right(screen: Control) -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(350, 0)
	box.add_theme_constant_override("separation", 4)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio = 1.4
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 6)
	scroll.add_child(inner)
	screen._tool_box = VBoxContainer.new()
	screen._tool_box.name = "ToolBox"
	screen._tool_box.add_theme_constant_override("separation", 3)
	inner.add_child(screen._tool_box)
	inner.add_child(HSeparator.new())
	screen._sel_box = VBoxContainer.new()
	screen._sel_box.name = "SelectionBox"
	screen._sel_box.add_theme_constant_override("separation", 3)
	inner.add_child(screen._sel_box)
	box.add_child(scroll)
	var head := HBoxContainer.new()
	screen._issues_header = Label.new()
	screen._issues_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(screen._issues_header)
	screen.live_validation = checkbox("UI_DEV_EDITOR_LIVE", true, func(_on): pass)
	head.add_child(screen.live_validation)
	head.add_child(button("UI_DEV_EDITOR_VALIDATE", screen.validate))
	box.add_child(head)
	var scroll_issues := ScrollContainer.new()
	scroll_issues.custom_minimum_size = Vector2(0, 170)
	scroll_issues.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_issues.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	screen.issue_list = VBoxContainer.new()
	screen.issue_list.name = "IssueList"
	screen.issue_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	screen.issue_list.add_theme_constant_override("separation", 1)
	scroll_issues.add_child(screen.issue_list)
	box.add_child(scroll_issues)
	return box


static func button(key: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = Texts.t(key)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(on_press)
	return b


static func checkbox(key: String, on: bool, on_toggle: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = Texts.t(key)
	c.button_pressed = on
	c.focus_mode = Control.FOCUS_NONE
	c.toggled.connect(on_toggle)
	return c
