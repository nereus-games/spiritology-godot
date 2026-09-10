## Écran de sélection des scénarios de test (dev).
##
## Liste les scénarios de [ScenarioCatalog] sous forme de boutons ; le choix pose
## `ScenarioCatalog.selected_id` et lance la scène d'exploration. Écran TEMPORAIRE (le vrai
## flux passera par l'écran-titre) — accessible aussi via le bouton MENU du HUD.
extends Control

const ScenarioCatalog := preload("res://scripts/dev/scenario_catalog.gd")
const EXPLORATION := "res://scenes/exploration/exploration.tscn"


func _ready() -> void:
	# L'exploration capture le curseur ; on le rend visible pour cliquer les boutons.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# En-tête FIXE (titre + réglages) et liste DÉROULANTE en dessous : les scénarios sont
	# désormais plus nombreux qu'un écran.
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)

	var title := Label.new()
	title.text = "Scénarios de test — exploration"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	box.add_child(_build_duo_row())
	box.add_child(_build_rival_den_row())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true  # naviguer au clavier fait défiler la liste
	box.add_child(scroll)

	# Le ScrollContainer étire son enfant sur toute la largeur : pour centrer la grille sous
	# l'en-tête, on la loge dans une rangée centrée plutôt que de compter sur ses size flags.
	var centered := HBoxContainer.new()
	centered.alignment = BoxContainer.ALIGNMENT_CENTER
	centered.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(centered)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 12)
	centered.add_child(grid)

	for scenario in ScenarioCatalog.list():
		var entry := VBoxContainer.new()
		entry.add_theme_constant_override("separation", 2)
		grid.add_child(entry)

		var button := Button.new()
		button.text = scenario.title
		button.custom_minimum_size = Vector2(460, 38)
		button.pressed.connect(_on_scenario_chosen.bind(scenario.id))
		entry.add_child(button)

		var desc := Label.new()
		desc.text = scenario.description
		desc.custom_minimum_size = Vector2(460, 0)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.add_theme_font_size_override("font_size", 12)
		desc.add_theme_color_override("font_color", Color(0.68, 0.70, 0.76))
		entry.add_child(desc)


## Réglage DEV du duo jouable : une liste par rôle, restreinte aux espèces que le mini-quiz
## peut donner à ce rôle (le principal n'a que 4 résultats possibles, le coéquipier 10 —
## doc « Mini Personality Quiz »). Les deux peuvent tomber sur la même espèce, c'est prévu.
func _build_duo_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(
		_species_picker(
			"Personnage principal",
			ScenarioCatalog.MAIN_SPECIES,
			ScenarioCatalog.main_species,
			func(id: StringName) -> void: ScenarioCatalog.main_species = id
		)
	)
	row.add_child(
		_species_picker(
			"Coéquipier",
			ScenarioCatalog.TEAMMATE_SPECIES,
			ScenarioCatalog.teammate_species,
			func(id: StringName) -> void: ScenarioCatalog.teammate_species = id
		)
	)
	return row


## Étiquette + liste déroulante d'espèces. `on_pick` reçoit le slug choisi.
func _species_picker(
	label_text: String, species: Array, current: StringName, on_pick: Callable
) -> Control:
	var cell := HBoxContainer.new()
	cell.add_theme_constant_override("separation", 6)

	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 13)
	cell.add_child(label)

	var picker := OptionButton.new()
	picker.custom_minimum_size = Vector2(180, 0)
	picker.add_theme_font_size_override("font_size", 13)
	for i in species.size():
		var id: StringName = species[i]
		picker.add_item(_species_name(id), i)
		if id == current:
			picker.select(i)
	picker.item_selected.connect(func(index: int) -> void: on_pick.call(species[index]))
	cell.add_child(picker)
	return cell


## Nom traduit de l'espèce (repli sur le slug si la clé n'est pas dans les .po).
func _species_name(id: StringName) -> String:
	var sp: SpeciesData = GameData.species(id)
	if sp == null:
		return String(id)
	var name := String(TranslationServer.translate(sp.name_key()))
	return String(id) if name == sp.name_key() else name


## Réglage DEV du DEN des rivaux. En vrai c'est le LEVEL DESIGN qui l'attribue, donjon par
## donjon ; ici on le choisit à la main pour les scénarios qui contiennent des rivaux. Les
## boutons E / M / L placent le curseur sur les ordres de grandeur de la doc.
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
		b.tooltip_text = "Ordre de grandeur de la doc"
		b.add_theme_font_size_override("font_size", 12)
		b.pressed.connect(func() -> void: slider.value = preset.value)
		row.add_child(b)

	# Valeur de départ : celle déjà choisie, sinon l'ordre de grandeur « early » de la doc.
	var start: int = ScenarioCatalog.rival_den_override
	if start <= 0:
		start = GameSession.RIVAL_DEN_EARLY
	slider.value = start
	ScenarioCatalog.rival_den_override = start
	value_label.text = _den_label(start)
	return row


## « DEN des rivaux : 100 — M (mid) » quand la valeur tombe sur un ordre de grandeur de la doc.
func _den_label(v: int) -> String:
	var tag := ""
	match v:
		GameSession.RIVAL_DEN_EARLY:
			tag = "  — E (early)"
		GameSession.RIVAL_DEN_MID:
			tag = "  — M (mid)"
		GameSession.RIVAL_DEN_LATE:
			tag = "  — L (late)"
	return "DEN des rivaux : %d%s" % [v, tag]


func _on_scenario_chosen(id: StringName) -> void:
	ScenarioCatalog.selected_id = id
	TransitionManager.change_scene(EXPLORATION)
