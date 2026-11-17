## The undo engine of the dungeon editor's model: a stack of commands, each a journal of what it
## overwrote, so that undo puts every old value back and redo every new one, exactly.
##
## Every operation of the model is ONE command, however many tiles it touches: `begin` and `commit`
## group several into one (a brush stroke does), and nesting is fine, only the outermost pair
## counts. A command that ends where it began is not recorded.
##
## The model extends this and holds the dungeon; the journal only knows that `plan` has
## dictionaries and fields it can write through [method _put], [method _erase] and [method _field].
##
## No `class_name` (the CLI class-cache trap): referenced by `extends` with a path.
extends RefCounted

signal changed

const Plan := preload("res://scripts/dungeon/dungeon_plan.gd")

enum Journal { DICT, FIELD }

## The working plan: what the editor edits, and what the checks compare.
var plan = Plan.new()

var _undo: Array = []
var _redo: Array = []
var _saved_at := 0
var _open = null
var _depth := 0

var dirty: bool:
	get:
		return _saved_at != _undo.size()


func can_undo() -> bool:
	return _undo.is_empty() == false


func can_redo() -> bool:
	return _redo.is_empty() == false


## The label of the command `undo` would revert, or "".
func undo_label() -> String:
	return _undo[-1]["label"] if not _undo.is_empty() else ""


func redo_label() -> String:
	return _redo[-1]["label"] if not _redo.is_empty() else ""


func undo() -> bool:
	if _open != null or _undo.is_empty():
		return false
	var cmd: Dictionary = _undo.pop_back()
	var entries: Array = cmd["entries"]
	for i in range(entries.size() - 1, -1, -1):
		_swap(entries[i])
	_redo.append(cmd)
	_reindex()
	changed.emit()
	return true


func redo() -> bool:
	if _open != null or _redo.is_empty():
		return false
	var cmd: Dictionary = _redo.pop_back()
	for entry in cmd["entries"]:
		_swap(entry)
	_undo.append(cmd)
	_reindex()
	changed.emit()
	return true


## Opens a command that the operations that follow all belong to, until the matching `commit`.
## Nesting is fine: only the outermost pair counts.
func begin(label: String) -> void:
	if _depth == 0:
		_open = {"label": label, "entries": [], "seen": {}}
	_depth += 1


func commit() -> void:
	_depth -= 1
	if _depth > 0:
		return
	_depth = 0
	var cmd = _open
	_open = null
	if cmd == null:
		return
	cmd.erase("seen")
	cmd["entries"] = _net_entries(cmd["entries"])
	if cmd["entries"].is_empty():
		return
	if _saved_at > _undo.size():
		_saved_at = -1  # the saved state was in the redo branch, now gone
	_undo.append(cmd)
	_redo.clear()
	_reindex()
	changed.emit()


## The entries of a command that changed something in the end: writing a key and writing back
## what it held is nothing.
func _net_entries(entries: Array) -> Array:
	var out: Array = []
	for entry in entries:
		if entry[0] == Journal.DICT:
			var dict: Dictionary = entry[1]
			if entry[3] == dict.has(entry[2]) and (not entry[3] or entry[4] == dict[entry[2]]):
				continue
		elif entry[4] == (entry[1] if entry[1] != null else self).get(entry[2]):
			continue
		out.append(entry)
	return out


func _swap(entry: Array) -> void:
	if entry[0] == Journal.DICT:
		var dict: Dictionary = entry[1]
		var key = entry[2]
		var had := dict.has(key)
		var current = _copy(dict.get(key))
		if entry[3]:
			dict[key] = entry[4]
		else:
			dict.erase(key)
		entry[3] = had
		entry[4] = current
	else:
		var obj = entry[1] if entry[1] != null else self
		var current = _copy(obj.get(entry[2]))
		obj.set(entry[2], entry[4])
		entry[4] = current


static func _copy(value):
	if value is Dictionary or value is Array:
		return value.duplicate(true)
	return value


## Which of the plan's own dictionaries `dict` is, so that a command logs a key once.
func _container_id(dict: Dictionary) -> int:
	var all := [
		plan.floor_tiles,
		plan.hole_tiles,
		plan.pit_tiles,
		plan.wall_tiles,
		plan.water_tiles,
		plan.tile_props,
		plan.zones,
		plan.rules
	]
	for i in all.size():
		if is_same(all[i], dict):
			return i
	return -1


func _log_dict(dict: Dictionary, key) -> void:
	var token := "d%d|%s" % [_container_id(dict), str(key)]
	if _open["seen"].has(token):
		return
	_open["seen"][token] = true
	_open["entries"].append([Journal.DICT, dict, key, dict.has(key), _copy(dict.get(key))])


func _put(dict: Dictionary, key, value) -> void:
	_log_dict(dict, key)
	dict[key] = value


func _erase(dict: Dictionary, key) -> void:
	if dict.has(key):
		_log_dict(dict, key)
		dict.erase(key)


func _field(obj, name: String, value) -> void:
	var token := "f%d|%s" % [obj.get_instance_id(), name]
	if not _open["seen"].has(token):
		_open["seen"][token] = true
		# The model itself is journalled as null: an entry that held `self` would be a reference
		# cycle (the model owns its undo stack), which Godot never frees.
		var target = null if obj == self else obj
		_open["entries"].append([Journal.FIELD, target, name, true, _copy(obj.get(name))])
	obj.set(name, value)


func _set_placements(list: Array) -> void:
	_field(plan, "placements", list)
	_reindex()


func _reindex() -> void:
	var index := {}
	for p in plan.placements:
		if not index.has(p["tile"]):
			index[p["tile"]] = []
		index[p["tile"]].append(p)
	plan.set("_by_tile", index)
