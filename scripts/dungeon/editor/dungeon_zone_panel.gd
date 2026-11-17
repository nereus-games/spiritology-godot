## The zone controls of the dungeon editor's tool options: pick a zone, make one, set its tags and
## its note, see how many tiles it has, delete it. Builds controls and edits nothing: each one
## calls the handler it was given.
##
## No `class_name` (the CLI class-cache trap): referenced by `preload`.
extends RefCounted

const Texts := preload("res://scripts/dungeon/editor/dungeon_editor_texts.gd")


## Fills `box`. `zone` is the zone being painted ("" for none), `zones` the plan's zones.
## `handlers`: `pick(name)` (an empty name for none), `create(name)`, `tags(text)`, `note(text)`
## and `delete()`.
static func build(box: Control, zones: Dictionary, zone: String, handlers: Dictionary) -> void:
	var names: Array = zones.keys()
	names.sort()
	var picker := OptionButton.new()
	picker.name = "ZonePicker"
	picker.add_item(Texts.t("UI_DEV_EDITOR_ZONE_NONE"))
	for i in names.size():
		picker.add_item(String(names[i]))
		if String(names[i]) == zone:
			picker.select(i + 1)
	picker.item_selected.connect(
		func(i: int) -> void: handlers["pick"].call("" if i == 0 else String(names[i - 1]))
	)
	box.add_child(picker)
	var make := HBoxContainer.new()
	var new_name := LineEdit.new()
	new_name.name = "ZoneName"
	new_name.placeholder_text = Texts.t("UI_DEV_EDITOR_ZONE_NAME")
	new_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	make.add_child(new_name)
	var create := Button.new()
	create.name = "ZoneCreate"
	create.text = Texts.t("UI_DEV_EDITOR_ZONE_NEW")
	create.focus_mode = Control.FOCUS_NONE
	create.pressed.connect(func(): handlers["create"].call(new_name.text.strip_edges()))
	make.add_child(create)
	box.add_child(make)
	if zone == "":
		return
	var data: Dictionary = zones[zone]
	var tags := LineEdit.new()
	tags.name = "ZoneTags"
	tags.text = ",".join(PackedStringArray(data["tags"]))
	tags.placeholder_text = Texts.t("UI_DEV_EDITOR_ZONE_TAGS")
	tags.tooltip_text = tags.placeholder_text
	tags.text_submitted.connect(handlers["tags"])
	tags.focus_exited.connect(func(): handlers["tags"].call(tags.text))
	box.add_child(tags)
	var note := LineEdit.new()
	note.name = "ZoneNote"
	note.text = data["props"].get("note", "")
	note.placeholder_text = Texts.t("UI_DEV_EDITOR_ZONE_NOTE")
	note.text_submitted.connect(handlers["note"])
	note.focus_exited.connect(func(): handlers["note"].call(note.text))
	box.add_child(note)
	var count := Label.new()
	count.add_theme_font_size_override("font_size", 12)
	count.text = Texts.t("UI_DEV_EDITOR_ZONE_TILES") % data["tiles"].size()
	if data["tiles"].is_empty():
		count.text += " " + Texts.t("UI_DEV_EDITOR_ZONE_EMPTY")
	box.add_child(count)
	var delete := Button.new()
	delete.text = Texts.t("UI_DEV_EDITOR_ZONE_DELETE")
	delete.focus_mode = Control.FOCUS_NONE
	delete.pressed.connect(handlers["delete"])
	box.add_child(delete)
