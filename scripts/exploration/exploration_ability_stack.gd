## The stack of known exploration abilities (element 4 of the HUD) and its USE / CANCEL submenu.
##
## All the logic lives here, none of the drawing: which abilities are listed, which can be used
## right now, and the flow from the stack to the submenu to the effect. The HUD only forwards
## keys to [method move], [method accept] and [method back], and draws [method entries] and
## [method submenu_options] as they stand. Not modal: movement stays possible while it is open.
##
## Decisions where the doc is silent (also recorded in the roadmap):
## - every ability the duo knows is listed, a spent one included but greyed, never hidden, as the
##   doc does for unusable encounter actions;
## - an ability is usable when it has not been used this visit and no Static Camouflage watch is
##   running (the watch's own choice is all there is while it lasts);
## - selecting a spent ability still opens its submenu, where USE is greyed and the cursor starts
##   on CANCEL; trying to USE it anyway posts the reason;
## - using an ability closes the whole stack; CANCEL goes back one level, to the stack.
##
## No `class_name` (the CLI class-cache trap): preloaded. References the GameSession autoload.
extends RefCounted

## Emitted whenever what the view shows has changed.
signal changed

enum Mode { CLOSED, STACK, SUBMENU }

const Catalog := preload("res://scripts/exploration/abilities/exploration_ability_catalog.gd")

## The submenu's two options, in order.
const USE := &"use"
const CANCEL := &"cancel"

var mode := Mode.CLOSED
var _ctx
var _selected := 0
var _sub_selected := 0
var _ids: Array[StringName] = []


func _init(ctx) -> void:
	_ctx = ctx


func is_open() -> bool:
	return mode != Mode.CLOSED


## The listed abilities, in a stable order (by identifier): each a dictionary with `id`,
## `label_key`, `usable` and `reason_key` (empty when usable). Spent ones stay listed.
func entries() -> Array:
	var out: Array = []
	for id in _known_ids():
		var reason := _reason_unusable(id)
		out.append(
			{
				"id": id,
				"label_key": _label_key(id),
				"usable": reason == "",
				"reason_key": reason,
			}
		)
	return out


## True when the duo knows at least one exploration ability: the HUD offers the stack only then.
func has_abilities() -> bool:
	return not _known_ids().is_empty()


func selected_id() -> StringName:
	if mode == Mode.CLOSED or _selected >= _ids.size():
		return &""
	return _ids[_selected]


func selected_index() -> int:
	return _selected


## The submenu's options: dictionaries with `id` (USE or CANCEL), `label_key` and `enabled`.
func submenu_options() -> Array:
	var usable := mode != Mode.CLOSED and _reason_unusable(selected_id()) == ""
	return [
		{"id": USE, "label_key": "UI_ABILITY_USE", "enabled": usable},
		{"id": CANCEL, "label_key": "UI_ABILITY_CANCEL", "enabled": true},
	]


func submenu_index() -> int:
	return _sub_selected


## Opens the stack on its first ability. False, and nothing opens, when none is known.
func open() -> bool:
	_ids = _known_ids()
	if _ids.is_empty():
		return false
	_selected = 0
	mode = Mode.STACK
	changed.emit()
	return true


func close() -> void:
	if mode == Mode.CLOSED:
		return
	mode = Mode.CLOSED
	changed.emit()


## Moves the cursor `step` positions, wrapping around, in the stack or in the submenu.
func move(step: int) -> void:
	match mode:
		Mode.STACK:
			_selected = wrapi(_selected + step, 0, _ids.size())
		Mode.SUBMENU:
			_sub_selected = wrapi(_sub_selected + step, 0, 2)
		_:
			return
	changed.emit()


## Confirms: in the stack, opens the selected ability's submenu; in the submenu, runs USE or
## goes back for CANCEL. Returns true when an ability was actually used.
func accept() -> bool:
	match mode:
		Mode.STACK:
			mode = Mode.SUBMENU
			# On a spent ability, USE is greyed: start on CANCEL.
			_sub_selected = 0 if _reason_unusable(selected_id()) == "" else 1
			changed.emit()
		Mode.SUBMENU:
			if submenu_options()[_sub_selected].id == CANCEL:
				back()
			else:
				return _use_selected()
	return false


## One level up: the submenu to the stack, the stack to nothing.
func back() -> void:
	match mode:
		Mode.SUBMENU:
			mode = Mode.STACK
			changed.emit()
		Mode.STACK:
			close()


func _use_selected() -> bool:
	var id := selected_id()
	var reason := _reason_unusable(id)
	if reason != "":
		_post(reason)
		return false
	var used: bool = Catalog.script_for(id).use(_ctx)
	if used:
		GameSession.mark_exploration_ability_used(id)
	close()
	return used


func _known_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for id in Catalog.known_for_duo():
		ids.append(id)
	ids.sort()
	return ids


## The translation key of why an ability cannot be used now, or "" when it can.
func _reason_unusable(id: StringName) -> String:
	if GameSession.is_exploration_ability_used(id):
		return "UI_ABILITY_SPENT"
	if _ctx != null and _ctx.dungeon != null and _ctx.dungeon.scouting.active:
		return "UI_ABILITY_BUSY"
	return ""


func _label_key(id: StringName) -> String:
	var ab: AbilityData = GameData.ability(id)
	return ab.name_key() if ab != null else String(id)


func _post(key: String) -> void:
	if _ctx != null and _ctx.dungeon != null:
		_ctx.dungeon.post_message(TranslationServer.translate(key))
