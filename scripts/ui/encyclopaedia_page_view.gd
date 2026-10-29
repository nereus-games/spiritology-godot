## A species' page, read only: what the encyclopaedia already knows, from
## [code]encyclopaedia_page_source.gd[/code], in two tabs — the page and its Forlorn variant.
##
## The fragment assembly desk is a screen of its own, opened from the encyclopaedia screen; this
## view only says that it can be. No text here that the page source does not give.
##
## No `class_name` (the CLI class-cache trap): the screen preloads this.
extends VBoxContainer

const GridLogic := preload("res://scripts/ui/encyclopaedia_grid_logic.gd")
const Art := preload("res://scripts/ui/encyclopaedia_art.gd")
const Source := preload("res://scripts/ui/encyclopaedia_page_source.gd")

const COLOR_DIM := Color(0.62, 0.65, 0.72)
const COLOR_TAB_ON := Color(0.95, 0.85, 0.45)

var forlorn_tab := false

var _tab_labels: Array[Label] = []
var _page: Control
var _forlorn: Control


func _init() -> void:
	add_theme_constant_override("separation", 12)


## Builds the page for `species_id`.
func setup(species_id: StringName) -> void:
	var info := Source.build(species_id)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 24)
	add_child(tabs)
	for key in ["UI_ENCYCLOPAEDIA_TAB_PAGE", "UI_ENCYCLOPAEDIA_TAB_FORLORN"]:
		var label := Label.new()
		label.text = tr(key)
		label.add_theme_font_size_override("font_size", 18)
		tabs.add_child(label)
		_tab_labels.append(label)

	_page = _build_page(info)
	_forlorn = _build_forlorn(Source.build_forlorn(species_id))
	add_child(_page)
	add_child(_forlorn)
	set_forlorn_tab(false)


## Switches between the page and its Forlorn tab.
func set_forlorn_tab(on: bool) -> void:
	forlorn_tab = on
	_page.visible = not on
	_forlorn.visible = on
	for i in _tab_labels.size():
		var active := (i == 1) == on
		_tab_labels[i].add_theme_color_override("font_color", COLOR_TAB_ON if active else COLOR_DIM)


func _build_page(info: Dictionary) -> Control:
	var sp: SpeciesData = info.species
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# Left: icon, name, spiricosm, completion.
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(230, 0)
	left.add_theme_constant_override("separation", 6)
	row.add_child(left)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(120, 120)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	icon.texture = Art.icon(sp.id)
	Art.apply_state(icon, GridLogic.icon_state(info.ifp))
	left.add_child(icon)
	var name_label := Label.new()
	name_label.text = tr(sp.name_key())
	name_label.add_theme_font_size_override("font_size", 28)
	left.add_child(name_label)
	left.add_child(_dim_label(tr("UI_ENCYCLOPAEDIA_SPIRICOSM") % tr(_spiricosm_key(sp))))
	left.add_child(_dim_label(tr("UI_ENCYCLOPAEDIA_COMPLETION") % info.completion))
	if Source.can_assemble(sp.id):
		var assemble := _dim_label(tr("UI_ENCYCLOPAEDIA_ASSEMBLE"))
		assemble.add_theme_color_override("font_color", COLOR_TAB_ON)
		left.add_child(assemble)

	# Centre: the illustration.
	var art := TextureRect.new()
	art.texture = Art.illustration(sp.id)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(art)

	# Right: weaknesses, talent, abilities, loot.
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(380, 0)
	right.add_theme_constant_override("separation", 6)
	row.add_child(right)

	right.add_child(_heading("UI_ENCYCLOPAEDIA_WEAKNESSES"))
	var weak := HBoxContainer.new()
	weak.add_theme_constant_override("separation", 10)
	for energy in info.weaknesses:
		var w := TextureRect.new()
		w.custom_minimum_size = Vector2(40, 40)
		w.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		w.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		w.texture = Art.weakness_icon(energy)
		w.tooltip_text = tr("TERM_ENERGY_%s" % GameEnums.Energy.keys()[energy])
		weak.add_child(w)
	right.add_child(weak)

	var talent: TalentData = info.talent
	if talent != null:
		right.add_child(_heading("UI_ENCYCLOPAEDIA_TALENT"))
		right.add_child(_text(tr(talent.name_key()), 18))
		# Not every talent has its description written in the .po files yet; a raw key on a
		# page would only look like a bug.
		if tr(talent.desc_key()) != talent.desc_key():
			right.add_child(_dim_label(tr(talent.desc_key())))

	right.add_child(_heading("UI_ENCYCLOPAEDIA_ABILITIES"))
	for ability in info.abilities:
		if ability.unlocked:
			var data: AbilityData = GameData.ability(ability.id)
			right.add_child(_text(tr(data.name_key()), 18))
		else:
			right.add_child(_dim_label(tr("UI_ENCYCLOPAEDIA_ABILITY_LOCKED") % ability.fragments))

	right.add_child(_heading("UI_ENCYCLOPAEDIA_LOOT"))
	if info.loot.is_empty():
		right.add_child(_dim_label(tr("UI_ENCYCLOPAEDIA_LOOT_NONE")))
	for object_id in info.loot:
		var obj: ObjectData = GameData.object(object_id)
		right.add_child(_text(tr(obj.name_key()) if obj != null else String(object_id), 16))
	return row


func _build_forlorn(info: Dictionary) -> Control:
	var sp: SpeciesData = info.species
	var box := VBoxContainer.new()
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	var name_label := Label.new()
	name_label.text = tr(sp.name_key())
	name_label.add_theme_font_size_override("font_size", 28)
	box.add_child(name_label)
	box.add_child(_dim_label(tr("UI_ENCYCLOPAEDIA_COMPLETION") % info.completion))
	if not info.open:
		box.add_child(_dim_label(tr("UI_ENCYCLOPAEDIA_FORLORN_LOCKED")))
	if info.ability != &"":
		box.add_child(_heading("UI_ENCYCLOPAEDIA_ABILITIES"))
		if info.unlocked:
			box.add_child(_text(tr(GameData.ability(info.ability).name_key()), 18))
		else:
			box.add_child(_dim_label(tr("UI_ENCYCLOPAEDIA_ABILITY_LOCKED") % info.fragments))
	if Source.can_assemble(sp.id, true):
		var assemble := _dim_label(tr("UI_ENCYCLOPAEDIA_ASSEMBLE"))
		assemble.add_theme_color_override("font_color", COLOR_TAB_ON)
		box.add_child(assemble)
	return box


func _heading(key: String) -> Label:
	var l := Label.new()
	l.text = tr(key)
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", COLOR_TAB_ON)
	l.add_theme_constant_override("line_spacing", 0)
	return l


func _text(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	return l


func _dim_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", COLOR_DIM)
	return l


## The translation key of the species' spiricosm.
func _spiricosm_key(sp: SpeciesData) -> String:
	return "TERM_SPIRICOSM_%s" % GameEnums.Spiricosm.keys()[sp.spiricosm]
