## The exploration contextual action menu (element 3 of the HUD, per the design doc's "User
## Interface").
##
## Shows the [ExplorationAction]s available to the player, supplied by
## [method DungeonManager.actions_for]: Dig, Recycle, Examine, Meditate, open a gateway, refresh,
## cross a cracked wall. Keyboard navigation: cycle the selection, then confirm; confirming
## invokes the selected action's `callable`. Not modal — movement stays possible — and
## deliberately built IN CODE and minimal. The final look (round icons, the USE/CANCEL submenu,
## alignment on the preselected icon) will be worked out in the engine.
##
## No `class_name` (the CLI class-cache trap): referenced by `preload`.
extends Control

## Emitted when the player confirms an action, after its callable has been invoked.
signal action_confirmed(id: StringName)

const SELECTED_COLOR := Color(1.0, 0.9, 0.4)
const NORMAL_COLOR := Color(0.9, 0.75, 0.75)

var _actions: Array = []
var _selected := 0
var _rows: Array[Label] = []
var _box: VBoxContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 4)
	# Anchored bottom-left and growing UPWARDS: the last entry (MENU) stays near the bottom and the
	# contextual actions stack above it, all of them visible.
	_box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_box.position += Vector2(20, -40)
	add_child(_box)
	visible = false


func has_actions() -> bool:
	return not _actions.is_empty()


## Id of the currently selected action, or &"" when there is none.
func selected_id() -> StringName:
	if _actions.is_empty():
		return &""
	return _actions[_selected].id


## Replaces the action list. Rebuilds only when the ids changed, which avoids flickering every
## frame, and keeps the selection on the same id where it can.
func set_actions(actions: Array) -> void:
	if _same_ids(actions):
		return
	var previously := selected_id()
	_actions = actions
	_selected = 0
	for i in _actions.size():
		if _actions[i].id == previously:
			_selected = i
			break
	_rebuild()


## Moves the selection `step` positions, wrapping around.
func cycle(step: int) -> void:
	if _actions.is_empty():
		return
	_selected = wrapi(_selected + step, 0, _actions.size())
	_update_highlight()


## Confirms the selected action: invokes its callable and emits [signal action_confirmed].
## Returns false when no action is available.
func confirm() -> bool:
	if _actions.is_empty():
		return false
	var action = _actions[_selected]
	if action.callable.is_valid():
		action.callable.call()
	action_confirmed.emit(action.id)
	return true


func _same_ids(actions: Array) -> bool:
	if actions.size() != _actions.size():
		return false
	for i in actions.size():
		if actions[i].id != _actions[i].id:
			return false
	return true


func _rebuild() -> void:
	for child in _box.get_children():
		child.queue_free()
	_rows.clear()
	for action in _actions:
		var label := Label.new()
		label.text = _label_for(action)
		_box.add_child(label)
		_rows.append(label)
	visible = not _actions.is_empty()
	_update_highlight()


## The label shown: `label_key` translated when available, otherwise a prettified id — a fallback
## while the UI_ACTION_* keys are missing from the .po files.
func _label_for(action) -> String:
	var t := String(TranslationServer.translate(action.label_key))
	if t == action.label_key:
		t = String(action.id).capitalize()
	return t


func _update_highlight() -> void:
	for i in _rows.size():
		_rows[i].add_theme_color_override(
			"font_color", SELECTED_COLOR if i == _selected else NORMAL_COLOR
		)
