## The encyclopaedia screen: the grid, and the page of the species picked on it.
##
## Reached today from the dev scenario picker, which stands in for the menu that does not exist
## yet. Run as a scene of its own, leaving it goes back to the picker; embedded in something else,
## it emits [signal closed] instead and the owner decides.
##
## Controls: arrows move the selector (or switch tabs on a page), accept opens a page (and, on a
## page with fragments, the assembly desk), cancel goes back one level.
## The list of species is every [SpeciesData], by identifier, which is a placeholder order:
## the doc does not say how pages are arranged.
##
## No `class_name` (the CLI class-cache trap).
extends Control

const GridView := preload("res://scripts/ui/encyclopaedia_grid_view.gd")
const PageView := preload("res://scripts/ui/encyclopaedia_page_view.gd")
const Recent := preload("res://scripts/ui/encyclopaedia_recent.gd")
const Source := preload("res://scripts/ui/encyclopaedia_page_source.gd")
const ASSEMBLY_SCENE := preload("res://scenes/ui/encyclopaedia_assembly.tscn")

const RETURN_SCENE := "res://scenes/dev/scenario_select.tscn"

signal closed

## Set before the node enters the tree to override where the selector starts; otherwise it is
## the species the encyclopaedia last gained information on.
var start_species: StringName = &""

## Whether the player is poisoned. Left unset, it is read from the exploration actor, if there is
## one; set directly by tests and by any owner that knows better. Above PSY 40 a poisoned player
## cannot open the encyclopaedia ([method GameSession.psy_forbids_while_poisoned]).
var poisoned: bool = false

var _grid: Control
var _page: Control
var _body: Control
var _hint: Label
var _assembly: Control


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

	if not poisoned:
		poisoned = _read_player_poison()
	if is_forbidden():
		_show_refusal()
	else:
		_show_grid()


## True when the PSY ladder keeps this view shut right now.
func is_forbidden() -> bool:
	return GameSession.psy_forbids_while_poisoned(poisoned)


func _read_player_poison() -> bool:
	var pl := get_tree().get_first_node_in_group("player")
	var aff = pl.get("affliction") if pl != null else null
	return aff != null and aff.has_poison()


func _show_refusal() -> void:
	var warning := Label.new()
	warning.text = tr("UI_PSY_POISON_FORBIDS_VIEW")
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warning.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_body.add_child(warning)
	_hint.text = tr("UI_ENCYCLOPAEDIA_HINT_REFUSED")


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
	_show_page_hint()


## Whether the page on show has fragments to assemble. The Forlorn tab is a placeholder.
func _can_assemble() -> bool:
	return _page != null and not _page.forlorn_tab and Source.can_assemble(start_species)


## Puts the assembly desk of the page on show over the screen. It is the same scene that anything
## else can instance; here it is freed when it says it is closed, and the page is built again,
## since its completion may have changed.
func _open_assembly() -> void:
	_assembly = ASSEMBLY_SCENE.instantiate()
	_assembly.species_id = start_species
	_assembly.closed.connect(_close_assembly)
	add_child(_assembly)


func _close_assembly() -> void:
	_assembly.queue_free()
	_assembly = null
	_show_page(start_species)


func _show_page_hint() -> void:
	var key := (
		"UI_ENCYCLOPAEDIA_HINT_PAGE_ASSEMBLE" if _can_assemble() else "UI_ENCYCLOPAEDIA_HINT_PAGE"
	)
	_hint.text = tr(key)


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
	if _assembly != null:
		return
	if event.is_action_pressed("ui_cancel"):
		if _page != null:
			_show_grid()
		else:
			_close()
	elif _page != null:
		if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
			_page.set_forlorn_tab(not _page.forlorn_tab)
			_show_page_hint()
		elif event.is_action_pressed("ui_accept") and _can_assemble():
			_open_assembly()
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
