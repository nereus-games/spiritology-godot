## The encyclopaedia's grid: one icon per species, no line between them, and a selector.
##
## Only the selector is drawn as a frame. An undiscovered species leaves its cell empty, since
## 0 IFP means no icon. The rules (wrap, nearest discovered, icon states) are in
## [code]encyclopaedia_grid_logic.gd[/code]; this node only draws them.
##
## No `class_name` (the CLI class-cache trap): the screen preloads this.
extends VBoxContainer

const GridLogic := preload("res://scripts/ui/encyclopaedia_grid_logic.gd")
const Art := preload("res://scripts/ui/encyclopaedia_art.gd")

const CELL := 84
const GAP := 6
const SELECTOR_COLOR := Color(0.95, 0.85, 0.45)

## The player picked a discovered species.
signal species_opened(species_id: StringName)

var _species: Array = []
var _discovered: Array = []
var _columns := 1
var _selected := -1
var _icons: Array[TextureRect] = []
var _frames: Array[Panel] = []
var _name_label: Label
var _completion_label: Label


func _init() -> void:
	add_theme_constant_override("separation", 10)


## Fills the grid from `species` (an array of [SpeciesData], in display order) and places the
## selector on `start_species` when it is discovered, near it otherwise.
func setup(species: Array, start_species: StringName) -> void:
	_species = species
	_columns = GridLogic.columns_for(species.size())
	var preferred := -1
	_discovered.clear()
	for i in species.size():
		var sp: SpeciesData = species[i]
		_discovered.append(GameSession.knows_species(sp.id))
		if sp.id == start_species:
			preferred = i
	_selected = GridLogic.start_index(_columns, _discovered, preferred)
	_build()
	_refresh_selection()


func selected_species() -> StringName:
	return _species[_selected].id if _selected >= 0 else &""


func selected_index() -> int:
	return _selected


func move_selector(dir: Vector2i) -> void:
	if _selected < 0:
		return
	_selected = GridLogic.move(_columns, _discovered, _selected, dir)
	_refresh_selection()


func open_selected() -> void:
	if _selected >= 0:
		species_opened.emit(_species[_selected].id)


func _build() -> void:
	var grid := GridContainer.new()
	grid.columns = _columns
	grid.add_theme_constant_override("h_separation", GAP)
	grid.add_theme_constant_override("v_separation", GAP)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_child(grid)
	for i in _species.size():
		var sp: SpeciesData = _species[i]
		var cell := Control.new()
		cell.custom_minimum_size = Vector2(CELL, CELL)
		cell.gui_input.connect(_on_cell_input.bind(i))
		grid.add_child(cell)

		var frame := Panel.new()
		frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var box := StyleBoxFlat.new()
		box.bg_color = Color(1, 1, 1, 0.07)
		box.border_color = SELECTOR_COLOR
		box.set_border_width_all(3)
		box.set_corner_radius_all(8)
		frame.add_theme_stylebox_override("panel", box)
		frame.visible = false
		cell.add_child(frame)
		_frames.append(frame)

		var icon := TextureRect.new()
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = 8
		icon.offset_top = 8
		icon.offset_right = -8
		icon.offset_bottom = -8
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = Art.icon(sp.id)
		Art.apply_state(icon, GridLogic.icon_state(GameSession.page_ifp(sp.id)))
		cell.add_child(icon)
		_icons.append(icon)

	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 20)
	add_child(_name_label)
	_completion_label = Label.new()
	_completion_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_completion_label.add_theme_color_override("font_color", Color(0.7, 0.72, 0.78))
	add_child(_completion_label)


func _refresh_selection() -> void:
	for i in _frames.size():
		_frames[i].visible = i == _selected
	if _selected < 0:
		_name_label.text = tr("UI_ENCYCLOPAEDIA_EMPTY")
		_completion_label.text = ""
		return
	var sp: SpeciesData = _species[_selected]
	_name_label.text = tr(sp.name_key())
	_completion_label.text = (tr("UI_ENCYCLOPAEDIA_COMPLETION") % GameSession.page_ifp(sp.id))


func _on_cell_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _discovered[index]:
			_selected = index
			_refresh_selection()
			open_selected()
