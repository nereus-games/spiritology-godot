## The encyclopaedia screen: the grid, and the page of the species picked on it.
##
## Reached today from the dev scenario picker, which stands in for the menu that does not exist
## yet. Run as a scene of its own, leaving it goes back to the picker; embedded in something else,
## it emits [signal closed] instead and the owner decides.
##
## Controls: arrows move the selector (or switch tabs on a page), accept opens a page, cancel
## goes back one level. The list of species is every [SpeciesData], by identifier, which is a
## placeholder order: the doc does not say how pages are arranged.
##
## No `class_name` (the CLI class-cache trap).
extends Control

const GridView := preload("res://scripts/ui/encyclopaedia_grid_view.gd")
const PageView := preload("res://scripts/ui/encyclopaedia_page_view.gd")
const Recent := preload("res://scripts/ui/encyclopaedia_recent.gd")

const RETURN_SCENE := "res://scenes/dev/scenario_select.tscn"

signal closed

## Set before the node enters the tree to override where the selector starts; otherwise it is
## the species the encyclopaedia last gained information on.
var start_species: StringName = &""

var _grid: Control
var _page: Control
var _body: Control
var _hint: Label


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var background := ColorRect.new()
	background.color = Color(0.07, 0.07, 0.1)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 28)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	var title := Label.new()
	title.text = tr("UI_ENCYCLOPAEDIA_TITLE")
	title.add_theme_font_size_override("font_size", 26)
	column.add_child(title)

	_body = Control.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_body)

	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 13)
	_hint.add_theme_color_override("font_color", Color(0.55, 0.58, 0.65))
	column.add_child(_hint)

	_show_grid()


## Species in display order: by identifier, a placeholder until the doc orders the pages.
func ordered_species() -> Array:
	var list: Array = GameData.all_species()
	list.sort_custom(func(a: SpeciesData, b: SpeciesData) -> bool: return str(a.id) < str(b.id))
	return list


func _show_grid() -> void:
	_clear_body()
	_grid = GridView.new()
	_grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_body.add_child(_grid)
	var preferred := start_species if start_species != &"" else Recent.last_species
	_grid.setup(ordered_species(), preferred)
	_grid.species_opened.connect(_show_page)
	_hint.text = tr("UI_ENCYCLOPAEDIA_HINT_GRID")


func _show_page(species_id: StringName) -> void:
	# Coming back from the page, the selector stays where it was.
	start_species = species_id
	_clear_body()
	_page = PageView.new()
	_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_body.add_child(_page)
	_page.setup(species_id)
	_hint.text = tr("UI_ENCYCLOPAEDIA_HINT_PAGE")


func _clear_body() -> void:
	for child in _body.get_children():
		child.queue_free()
		_body.remove_child(child)
	_grid = null
	_page = null


func _close() -> void:
	closed.emit()
	if get_tree().current_scene == self:
		TransitionManager.change_scene(RETURN_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _page != null:
			_show_grid()
		else:
			_close()
	elif _page != null:
		if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
			_page.set_forlorn_tab(not _page.forlorn_tab)
		else:
			return
	elif _grid != null:
		if event.is_action_pressed("ui_left"):
			_grid.move_selector(Vector2i.LEFT)
		elif event.is_action_pressed("ui_right"):
			_grid.move_selector(Vector2i.RIGHT)
		elif event.is_action_pressed("ui_up"):
			_grid.move_selector(Vector2i.UP)
		elif event.is_action_pressed("ui_down"):
			_grid.move_selector(Vector2i.DOWN)
		elif event.is_action_pressed("ui_accept"):
			_grid.open_selected()
		else:
			return
	else:
		return
	get_viewport().set_input_as_handled()
