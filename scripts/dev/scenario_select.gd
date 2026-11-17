## The dev test-scenario selection screen.
##
## Lists [ScenarioCatalog]'s scenarios as buttons; picking one sets `ScenarioCatalog.selected_id`
## and launches the exploration scene. TEMPORARY — the real flow will go through the title
## screen. Also reachable from the HUD's MENU button.
extends Control

const ScenarioCatalog := preload("res://scripts/dev/scenario_catalog.gd")
const MapParser := preload("res://scripts/dungeon/dungeon_map_parser.gd")
const Validator := preload("res://scripts/dungeon/dungeon_validator.gd")
const EditorLaunch := preload("res://scripts/dungeon/editor/dungeon_editor_launch.gd")
const Util := preload("res://scripts/dungeon/editor/dungeon_editor_util.gd")
const EXPLORATION := "res://scenes/exploration/exploration.tscn"
## The dungeon editor: a dev tool, reached from here and from nowhere else.
const DUNGEON_EDITOR := "res://scenes/dev/dungeon_editor.tscn"
## The encyclopaedia, until a menu exists to reach it from.
const ENCYCLOPAEDIA := "res://scenes/ui/encyclopaedia.tscn"
const EncyclopaediaSample := preload("res://scripts/dev/encyclopaedia_sample.gd")


func _ready() -> void:
	# Exploration captures the cursor; make it visible again so the buttons can be clicked.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# A FIXED header (title plus settings) with a SCROLLING list below it: there are now more
	# scenarios than fit on a screen.
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)

	var title := Label.new()
	title.text = tr("UI_DEV_SCENARIOS_TITLE")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	box.add_child(_build_duo_row())
	box.add_child(_build_rival_den_row())
	box.add_child(_build_encyclopaedia_row())

	# Two tabs under the shared header: the test scenarios, which exercise one mechanism each, and
	# the real dungeons.
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(tabs)

	var grid := _scrolling_grid(tabs, 2)
	tabs.set_tab_title(0, tr("UI_DEV_TAB_SCENARIOS"))

	var dungeon_list := _scrolling_grid(tabs, 1)
	tabs.set_tab_title(1, tr("UI_DEV_TAB_DUNGEONS"))
	_fill_dungeons(dungeon_list)

	for scenario in ScenarioCatalog.list():
		var entry := VBoxContainer.new()
		entry.add_theme_constant_override("separation", 2)
		grid.add_child(entry)

		var button := Button.new()
		button.text = String(TranslationServer.translate(scenario.name_key()))
		button.custom_minimum_size = Vector2(460, 38)
		button.pressed.connect(_on_scenario_chosen.bind(scenario.id))
		entry.add_child(button)

		var desc := Label.new()
		desc.text = String(TranslationServer.translate(scenario.desc_key()))
		desc.custom_minimum_size = Vector2(460, 0)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.add_theme_font_size_override("font_size", 12)
		desc.add_theme_color_override("font_color", Color(0.68, 0.70, 0.76))
		entry.add_child(desc)


## A tab holding a scrolling grid of `columns` columns, centred under the header. Returns the
## grid; the tab is added to `tabs`.
func _scrolling_grid(tabs: TabContainer, columns: int) -> GridContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true  # keyboard navigation scrolls the list along
	tabs.add_child(scroll)

	# A ScrollContainer stretches its child to the full width, so to centre the grid it goes
	# inside a centred row rather than relying on its size flags.
	var centered := HBoxContainer.new()
	centered.alignment = BoxContainer.ALIGNMENT_CENTER
	centered.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(centered)

	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 12)
	centered.add_child(grid)
	return grid


## The real dungeons ([method ScenarioCatalog.real_dungeon_ids]), each with what the validator
## makes of its maps. One with maps can be entered, faults or not — they are reported beside it; one
## with none is greyed out with the reason — and, with no dungeon at all, a line says so.
func _fill_dungeons(grid: GridContainer) -> void:
	var make := Button.new()
	make.text = tr("UI_DEV_DUNGEON_NEW")
	make.custom_minimum_size = Vector2(460, 34)
	make.set_meta("role", "new")
	make.pressed.connect(_on_new_dungeon_pressed)
	grid.add_child(make)
	var ids := ScenarioCatalog.real_dungeon_ids()
	if ids.is_empty():
		var empty := Label.new()
		empty.text = tr("UI_DEV_DUNGEONS_EMPTY")
		empty.add_theme_color_override("font_color", Color(0.68, 0.70, 0.76))
		grid.add_child(empty)
		return
	for id in ids:
		var entry := VBoxContainer.new()
		entry.add_theme_constant_override("separation", 2)
		grid.add_child(entry)

		# The dungeon to walk through, and beside it, when it has maps, the editor.
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		entry.add_child(row)
		var button := Button.new()
		button.text = _dungeon_name(id)
		button.custom_minimum_size = Vector2(380, 38)
		button.set_meta("role", "play")
		var has_maps := MapParser.slugs().has(id)
		button.disabled = not has_maps
		if has_maps:
			button.pressed.connect(_on_dungeon_chosen.bind(id))
		row.add_child(button)
		if has_maps:
			var edit := Button.new()
			edit.text = tr("UI_DEV_DUNGEON_EDIT")
			edit.custom_minimum_size = Vector2(74, 38)
			edit.set_meta("role", "edit")
			edit.pressed.connect(_on_dungeon_edit.bind(id))
			row.add_child(edit)

		if not has_maps:
			entry.add_child(_dim_label(tr("UI_DEV_DUNGEON_NO_MAPS")))
		else:
			var issues: Array = Validator.new().validate(
				MapParser.load_slug(id), GameData.dungeon(id)
			)
			var errors := Validator.error_count(issues)
			entry.add_child(
				_dim_label(tr("UI_DEV_DUNGEON_VERDICT") % [errors, issues.size() - errors])
			)


func _on_dungeon_edit(id: StringName) -> void:
	EditorLaunch.edit(id)
	TransitionManager.change_scene(DUNGEON_EDITOR)


## Asks for the name of a new dungeon, which is the folder it will live in, then opens the editor
## on an empty one. The name is checked as it is typed: the button stays off until it is usable.
func _on_new_dungeon_pressed() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.name = "NewDungeonDialog"
	dialog.title = tr("UI_DEV_DUNGEON_NEW")
	dialog.ok_button_text = tr("UI_DEV_DUNGEON_NEW_CREATE")
	dialog.cancel_button_text = tr("UI_DEV_EDITOR_CANCEL")
	var box := VBoxContainer.new()
	dialog.add_child(box)
	var prompt := Label.new()
	prompt.text = tr("UI_DEV_DUNGEON_NEW_PROMPT")
	prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt.custom_minimum_size = Vector2(420, 0)
	box.add_child(prompt)
	var field := LineEdit.new()
	field.name = "SlugField"
	box.add_child(field)
	var problem := _dim_label("")
	box.add_child(problem)
	var check := func(text: String) -> void:
		var taken := ScenarioCatalog.real_dungeon_ids().has(StringName(text))
		var bad := not Util.valid_slug(text)
		problem.text = (
			tr("UI_DEV_DUNGEON_NEW_TAKEN")
			if taken
			else (tr("UI_DEV_DUNGEON_NEW_BAD") if bad and text != "" else "")
		)
		dialog.get_ok_button().disabled = bad or taken
	field.text_changed.connect(check)
	dialog.confirmed.connect(
		func() -> void:
			EditorLaunch.new_dungeon(StringName(field.text))
			TransitionManager.change_scene(DUNGEON_EDITOR)
	)
	add_child(dialog)
	dialog.popup_centered()
	check.call("")
	field.grab_focus()


## The dungeon's translated name, or its id while it has none.
func _dungeon_name(id: StringName) -> String:
	var key := "DUNGEON_%s_NAME" % GameEnums.key_token(id)
	var name := String(TranslationServer.translate(key))
	return String(id) if name == key else name


func _dim_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.68, 0.70, 0.76))
	return label


## DEV control for the playable duo: one list per role, restricted to the species the mini quiz
## can give that role — the main character has only 4 possible results, the teammate 10, per the
## design doc's "Mini Personality Quiz". Both can land on the same species, by design.
func _build_duo_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(
		_species_picker(
			tr("UI_DEV_MAIN_CHARACTER"),
			ScenarioCatalog.MAIN_SPECIES,
			ScenarioCatalog.main_species,
			func(id: StringName) -> void: ScenarioCatalog.main_species = id
		)
	)
	row.add_child(
		_species_picker(
			tr("UI_DEV_TEAMMATE"),
			ScenarioCatalog.TEAMMATE_SPECIES,
			ScenarioCatalog.teammate_species,
			func(id: StringName) -> void: ScenarioCatalog.teammate_species = id
		)
	)
	return row


## A label plus a species dropdown. `on_pick` receives the slug chosen.
func _species_picker(
	label_text: String, species: Array, current: StringName, on_pick: Callable
) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 13)
	row.add_child(label)

	var picker := OptionButton.new()
	picker.custom_minimum_size = Vector2(180, 0)
	picker.add_theme_font_size_override("font_size", 13)
	for i in species.size():
		var id: StringName = species[i]
		picker.add_item(_species_name(id), i)
		if id == current:
			picker.select(i)
	picker.item_selected.connect(func(index: int) -> void: on_pick.call(species[index]))
	row.add_child(picker)
	return row


## The species' translated name, falling back to the slug when the key is missing from the .po.
func _species_name(id: StringName) -> String:
	var sp: SpeciesData = GameData.species(id)
	if sp == null:
		return String(id)
	var name := String(TranslationServer.translate(sp.name_key()))
	return String(id) if name == sp.name_key() else name


## DEV control for rival DEN. In the real game LEVEL DESIGN assigns it, dungeon by dungeon; here
## it is picked by hand for the scenarios that contain rivals. The E / M / L buttons put the
## slider on the design doc's ballpark figures.
func _build_rival_den_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER

	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(230, 0)
	value_label.add_theme_font_size_override("font_size", 13)

	var slider := HSlider.new()
	slider.min_value = 10
	slider.max_value = 150
	slider.step = 5
	slider.custom_minimum_size = Vector2(260, 0)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	slider.value_changed.connect(
		func(v: float) -> void:
			ScenarioCatalog.rival_den_override = int(v)
			value_label.text = _den_label(int(v))
	)

	row.add_child(value_label)
	row.add_child(slider)
	for preset in [
		{"tag": "E", "value": GameSession.RIVAL_DEN_EARLY},
		{"tag": "M", "value": GameSession.RIVAL_DEN_MID},
		{"tag": "L", "value": GameSession.RIVAL_DEN_LATE},
	]:
		var b := Button.new()
		b.text = "%s · %d" % [preset.tag, preset.value]
		b.tooltip_text = tr("UI_DEV_RIVAL_DEN_TOOLTIP")
		b.add_theme_font_size_override("font_size", 12)
		b.pressed.connect(func() -> void: slider.value = preset.value)
		row.add_child(b)

	# Starting value: whatever was already picked, otherwise the design doc's "early" figure.
	var start: int = ScenarioCatalog.rival_den_override
	if start <= 0:
		start = GameSession.RIVAL_DEN_EARLY
	slider.value = start
	ScenarioCatalog.rival_den_override = start
	value_label.text = _den_label(start)
	return row


## DEV: two buttons into the encyclopaedia — with the session's own progress, and with a
## deterministic sample that overwrites it (every icon state shows).
func _build_encyclopaedia_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var plain := Button.new()
	plain.text = tr("UI_DEV_ENCYCLOPAEDIA")
	plain.pressed.connect(func() -> void: TransitionManager.change_scene(ENCYCLOPAEDIA))
	row.add_child(plain)
	var sample := Button.new()
	sample.text = tr("UI_DEV_ENCYCLOPAEDIA_SAMPLE")
	sample.pressed.connect(
		func() -> void:
			EncyclopaediaSample.fill()
			TransitionManager.change_scene(ENCYCLOPAEDIA)
	)
	row.add_child(sample)
	return row


## Appends the design doc's tag when the value lands on one of its ballpark figures.
func _den_label(v: int) -> String:
	var tag := ""
	match v:
		GameSession.RIVAL_DEN_EARLY:
			tag = tr("UI_DEV_RIVAL_DEN_EARLY")
		GameSession.RIVAL_DEN_MID:
			tag = tr("UI_DEV_RIVAL_DEN_MID")
		GameSession.RIVAL_DEN_LATE:
			tag = tr("UI_DEV_RIVAL_DEN_LATE")
	return tr("UI_DEV_RIVAL_DEN") % [v, tag]


func _on_dungeon_chosen(id: StringName) -> void:
	ScenarioCatalog.selected_dungeon = id
	TransitionManager.change_scene(EXPLORATION)


func _on_scenario_chosen(id: StringName) -> void:
	ScenarioCatalog.selected_dungeon = &""
	ScenarioCatalog.selected_id = id
	TransitionManager.change_scene(EXPLORATION)
