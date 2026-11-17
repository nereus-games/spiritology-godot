## Builds the property form of the dungeon editor from the kinds table: one row per property,
## its widget chosen by the property's declared type.
##
##   bool   CheckBox            int, float   SpinBox          str, list   LineEdit
##   enum   OptionButton        dir          N E S W buttons
##   tile, tiles   LineEdit (cell names) and a button to pick on the map instead
##
## A property that is not set is shown dimmed, and a button beside it clears one that is. The
## form edits nothing itself: every change calls `on_edit(next, structural)` with the complete new
## properties (read afresh from `get_props` each time, so that two edits in a row do not undo each
## other), and the owner decides what to do with them. `structural` says the form should be
## rebuilt (a property was cleared or added, a choice made); a text or number being typed in is
## left alone, so that it keeps the focus.
##
## Names of kinds and properties are the format's own identifiers, shown as they are written in
## the files; every sentence goes through a translation key.
##
## No `class_name` (the CLI class-cache trap): referenced by `preload`.
extends RefCounted

const Kinds := preload("res://scripts/dungeon/dungeon_kinds.gd")
const Writer := preload("res://scripts/dungeon/dungeon_map_writer.gd")

const DIRS: Array[String] = ["N", "E", "S", "W"]
const NAME_WIDTH := 92


## The names a form for `kind` shows, in table order: its own properties, then the common ones,
## then any other property `props` already has (`custom.*`, or a name the table does not know).
## An empty `kind` is a bare tile, which has the common ones only.
static func names_for(kind: StringName, props: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if Kinds.KINDS.has(kind):
		for name in Kinds.KINDS[kind]["props"]:
			out.append(name)
	for name in Kinds.COMMON:
		out.append(name)
	var extra: Array[String] = []
	for name in props:
		if not out.has(name):
			extra.append(name)
	extra.sort()
	out.append_array(extra)
	return out


## Fills `parent` with the rows. `y` is the storey tile references are read on. `on_pick` is
## called with (name, type) when a tile button is pressed; `picking` is the name being picked,
## shown as pressed.
static func build(
	parent: Control,
	kind: StringName,
	get_props: Callable,
	y: int,
	on_edit: Callable,
	on_pick: Callable,
	picking: String = ""
) -> void:
	var props: Dictionary = get_props.call()
	for name in names_for(kind, props):
		var type := Kinds.prop_type(kind, name)
		if type == "":
			type = "str"
		parent.add_child(_row(name, type, get_props, y, on_edit, on_pick, picking))
	parent.add_child(_custom_row(get_props, on_edit))


static func _row(
	name: String,
	type: String,
	get_props: Callable,
	y: int,
	on_edit: Callable,
	on_pick: Callable,
	picking: String
) -> Control:
	var props: Dictionary = get_props.call()
	var row := HBoxContainer.new()
	row.name = "Row_" + name
	row.add_theme_constant_override("separation", 4)
	var is_set := props.has(name)
	var clear := Button.new()
	clear.text = "x"
	clear.flat = true
	clear.focus_mode = Control.FOCUS_NONE
	clear.disabled = not is_set
	clear.tooltip_text = _t("UI_DEV_EDITOR_PROP_CLEAR")
	clear.pressed.connect(_commit.bind(get_props, name, null, on_edit, true))
	row.add_child(clear)
	var label := Label.new()
	label.text = name
	label.tooltip_text = type
	label.custom_minimum_size = Vector2(NAME_WIDTH, 0)
	label.clip_text = true
	label.add_theme_font_size_override("font_size", 12)
	row.add_child(label)
	var widget := _widget(name, type, get_props, y, on_edit, on_pick, picking)
	widget.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(widget)
	row.modulate.a = 1.0 if is_set else 0.6
	return row


static func _widget(
	name: String,
	type: String,
	get_props: Callable,
	y: int,
	on_edit: Callable,
	on_pick: Callable,
	picking: String
) -> Control:
	var props: Dictionary = get_props.call()
	var value = props.get(name)
	if type.begins_with("enum:"):
		var options := type.substr(5).split("|")
		var option := OptionButton.new()
		for o in options:
			option.add_item(o)
		option.selected = options.find(value) if value != null else -1
		option.item_selected.connect(
			func(i: int) -> void: _commit(get_props, name, options[i], on_edit, true)
		)
		return option
	match type:
		"bool":
			var box := CheckBox.new()
			box.button_pressed = bool(value) if value != null else false
			box.toggled.connect(func(on: bool) -> void: _commit(get_props, name, on, on_edit, true))
			return box
		"int", "float":
			var spin := SpinBox.new()
			spin.min_value = -99999
			spin.max_value = 99999
			spin.step = 1.0 if type == "int" else 0.01
			spin.value = float(value) if value != null else 0.0
			spin.value_changed.connect(
				func(v: float) -> void:
					_commit(get_props, name, int(v) if type == "int" else v, on_edit, false)
			)
			return spin
		"dir":
			return _dir_buttons(name, get_props, on_edit)
		"tile", "tiles":
			return _tile_field(name, type, get_props, y, on_edit, on_pick, picking)
	var edit := LineEdit.new()
	edit.text = _text_of(type, value, y)
	var send := func(text: String) -> void:
		if text == _text_of(type, value, y):
			return
		var stripped := text.strip_edges()
		if stripped == "":
			_commit(get_props, name, null, on_edit, true)
		elif type == "list":
			var items: Array[String] = []
			for part in stripped.split(",", false):
				items.append(part.strip_edges())
			_commit(get_props, name, items, on_edit, false)
		else:
			_commit(get_props, name, stripped, on_edit, false)
	edit.text_submitted.connect(send)
	edit.focus_exited.connect(func() -> void: send.call(edit.text))
	return edit


static func _dir_buttons(name: String, get_props: Callable, on_edit: Callable) -> Control:
	var props: Dictionary = get_props.call()
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var group := ButtonGroup.new()
	group.allow_unpress = true
	for letter in DIRS:
		var b := Button.new()
		b.text = letter
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(26, 0)
		b.button_pressed = props.get(name) == Kinds.DIRECTIONS[letter]
		b.pressed.connect(
			func() -> void:
				_commit(
					get_props,
					name,
					Kinds.DIRECTIONS[letter] if b.button_pressed else null,
					on_edit,
					true
				)
		)
		box.add_child(b)
	return box


static func _tile_field(
	name: String,
	type: String,
	get_props: Callable,
	y: int,
	on_edit: Callable,
	on_pick: Callable,
	picking: String
) -> Control:
	var props: Dictionary = get_props.call()
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var edit := LineEdit.new()
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.text = _text_of(type, props.get(name), y)
	var send := func(text: String) -> void:
		var stripped := text.strip_edges()
		if stripped == _text_of(type, props.get(name), y):
			return
		if stripped == "":
			_commit(get_props, name, null, on_edit, true)
			return
		var tiles: Array[Vector3i] = []
		for part in stripped.split(";", false):
			var t = Kinds.parse_tile(part, y)
			if t == null:
				edit.text = _text_of(type, props.get(name), y)
				return
			tiles.append(t)
		if type == "tile":
			_commit(get_props, name, tiles[0], on_edit, false)
		else:
			_commit(get_props, name, tiles, on_edit, false)
	edit.text_submitted.connect(send)
	edit.focus_exited.connect(func() -> void: send.call(edit.text))
	box.add_child(edit)
	var pick := Button.new()
	pick.text = "+" if type == "tiles" else "o"
	pick.toggle_mode = true
	pick.button_pressed = picking == name
	pick.focus_mode = Control.FOCUS_NONE
	pick.tooltip_text = _t("UI_DEV_EDITOR_PROP_PICK")
	pick.pressed.connect(func() -> void: on_pick.call(name, type))
	box.add_child(pick)
	return box


## A row to add a `custom.<name>` property: the escape hatch for a case the table does not know.
static func _custom_row(get_props: Callable, on_edit: Callable) -> Control:
	var row := HBoxContainer.new()
	row.name = "CustomRow"
	row.add_theme_constant_override("separation", 4)
	var key := LineEdit.new()
	key.placeholder_text = _t("UI_DEV_EDITOR_CUSTOM_NAME")
	key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(key)
	var value := LineEdit.new()
	value.placeholder_text = _t("UI_DEV_EDITOR_CUSTOM_VALUE")
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(value)
	var add := Button.new()
	add.text = "+"
	add.tooltip_text = _t("UI_DEV_EDITOR_CUSTOM_ADD")
	add.pressed.connect(
		func() -> void:
			var n := key.text.strip_edges().trim_prefix("custom.")
			if n == "" or value.text.strip_edges() == "":
				return
			_commit(get_props, "custom." + n, value.text.strip_edges(), on_edit, true)
	)
	row.add_child(add)
	return row


## `props` with `name` set to `value` (cleared when null), handed to `on_edit`.
static func _commit(
	get_props: Callable, name: String, value, on_edit: Callable, structural: bool
) -> void:
	var next: Dictionary = get_props.call().duplicate(true)
	if value == null:
		next.erase(name)
	else:
		next[name] = value
	on_edit.call(next, structural)


static func _text_of(type: String, value, y: int) -> String:
	if value == null:
		return ""
	if value is Array:
		var parts: Array[String] = []
		for item in value:
			parts.append(Writer.tile_ref(item, y) if item is Vector3i else str(item))
		return (";" if type == "tiles" else ",").join(parts)
	if value is Vector3i:
		return Writer.tile_ref(value, y)
	return str(value)


static func _t(key: String) -> String:
	return String(TranslationServer.translate(key))
