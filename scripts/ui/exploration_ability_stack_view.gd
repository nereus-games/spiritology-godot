## Draws the stack of known exploration abilities (element 4 of the HUD) and its USE / CANCEL
## submenu. Thin on purpose: every decision is in [code]exploration_ability_stack.gd[/code], this
## only redraws when that object says it changed. Placeholder look, in code, left of the screen,
## midway down: round icons and the final layout are art.
##
## No `class_name` (the CLI class-cache trap): preloaded.
extends Control

const Stack := preload("res://scripts/exploration/exploration_ability_stack.gd")

const SELECTED_COLOR := Color(1.0, 0.9, 0.4)
const NORMAL_COLOR := Color(0.9, 0.75, 0.75)
const GREYED_COLOR := Color(0.5, 0.5, 0.5)

var _stack
var _box: VBoxContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 4)
	_box.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	_box.position += Vector2(20, 0)
	add_child(_box)
	visible = false


## Shows `stack` (an ExplorationAbilityStack) and redraws whenever it changes.
func bind(stack) -> void:
	_stack = stack
	_stack.changed.connect(_redraw)
	_redraw()


func _redraw() -> void:
	if _box == null:
		return
	for child in _box.get_children():
		child.queue_free()
	visible = _stack != null and _stack.is_open()
	if not visible:
		return
	var entries: Array = _stack.entries()
	for i in entries.size():
		var entry: Dictionary = entries[i]
		var selected: bool = i == _stack.selected_index()
		var line := Label.new()
		line.text = ("> " if selected else "  ") + _tr(entry.label_key)
		line.add_theme_color_override("font_color", _row_color(selected, entry.usable))
		_box.add_child(line)
		if selected and _stack.mode == Stack.Mode.SUBMENU:
			_add_submenu()


func _add_submenu() -> void:
	var options: Array = _stack.submenu_options()
	for j in options.size():
		var line := Label.new()
		line.text = "      " + _tr(options[j].label_key)
		line.add_theme_color_override(
			"font_color", _row_color(j == _stack.submenu_index(), options[j].enabled)
		)
		_box.add_child(line)


func _row_color(selected: bool, enabled: bool) -> Color:
	if not enabled:
		return GREYED_COLOR
	return SELECTED_COLOR if selected else NORMAL_COLOR


func _tr(key: String) -> String:
	var t := String(TranslationServer.translate(key))
	return t if t != key else key.capitalize()
