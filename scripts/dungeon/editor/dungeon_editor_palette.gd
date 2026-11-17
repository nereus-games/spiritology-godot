## The palette of the dungeon editor: one toggle button per tool, in sections. The placements are
## generated from the kinds table, so a kind added there appears here with nothing else to change.
##
## No `class_name` (the CLI class-cache trap): referenced by `preload`.
extends RefCounted

const Kinds := preload("res://scripts/dungeon/dungeon_kinds.gd")
const Texts := preload("res://scripts/dungeon/editor/dungeon_editor_texts.gd")

const TERRAIN_TOOLS: Array[String] = ["floor", "ice", "water", "wall", "empty", "hole"]
const DIM := Color(0.68, 0.70, 0.76)


## The scrolling palette. `buttons` is filled with tool id -> its button; `on_pick` is called with
## the id when one is pressed. Tool ids: `select`, `erase`, `terrain:<name>`, `entrance`, `exit`,
## `exit_remove`, `kind:<kind>`, `zone_paint`, `zone_erase`, `emerge`.
static func build(buttons: Dictionary, on_pick: Callable) -> Control:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(176, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 2)
	scroll.add_child(box)
	var group := ButtonGroup.new()
	_section(box, "UI_DEV_EDITOR_SECTION_TOOLS")
	_tool(box, group, buttons, on_pick, "select", Texts.t("UI_DEV_EDITOR_TOOL_SELECT"), "")
	_tool(box, group, buttons, on_pick, "erase", Texts.t("UI_DEV_EDITOR_TOOL_ERASE"), "")
	_section(box, "UI_DEV_EDITOR_SECTION_TERRAIN")
	for terrain in TERRAIN_TOOLS:
		var label := Texts.t("UI_DEV_EDITOR_TERRAIN_" + terrain.to_upper())
		_tool(box, group, buttons, on_pick, "terrain:" + terrain, label, "")
	_section(box, "UI_DEV_EDITOR_SECTION_ENTRANCE")
	for id in ["entrance", "exit", "exit_remove"]:
		_tool(box, group, buttons, on_pick, id, Texts.t("UI_DEV_EDITOR_TOOL_" + id.to_upper()), "")
	_section(box, "UI_DEV_EDITOR_SECTION_PLACEMENTS")
	for kind in Kinds.KINDS:
		var id := "kind:" + String(kind)
		_tool(box, group, buttons, on_pick, id, Texts.kind_label(kind), String(kind))
	_section(box, "UI_DEV_EDITOR_SECTION_ZONES")
	for id in ["zone_paint", "zone_erase"]:
		_tool(box, group, buttons, on_pick, id, Texts.t("UI_DEV_EDITOR_TOOL_" + id.to_upper()), "")
	_section(box, "UI_DEV_EDITOR_SECTION_WATER")
	_tool(box, group, buttons, on_pick, "emerge", Texts.t("UI_DEV_EDITOR_TOOL_EMERGE"), "")
	buttons["select"].button_pressed = true
	return scroll


static func _section(box: VBoxContainer, key: String) -> void:
	var label := Label.new()
	label.text = Texts.t(key)
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", DIM)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_top", 8)
	pad.add_child(label)
	box.add_child(pad)


static func _tool(
	box: VBoxContainer,
	group: ButtonGroup,
	buttons: Dictionary,
	on_pick: Callable,
	id: String,
	text: String,
	tip: String
) -> void:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.toggle_mode = true
	b.button_group = group
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(on_pick.bind(id))
	b.name = "Tool_" + id.replace(":", "_")
	box.add_child(b)
	buttons[id] = b
