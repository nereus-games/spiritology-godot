## Headless check of the dev selection screen's two tabs: test scenarios, and real dungeons.
## A dungeon that a scenario runs under is a test fixture and belongs to the first tab only.
##
## Run with: Godot --headless --path . res://scenes/dev/scenario_select_check.tscn
## As a start scene rather than --script; see geometry_check.gd.
extends Node

const ScenarioCatalog := preload("res://scripts/dev/scenario_catalog.gd")
const MapParser := preload("res://scripts/dungeon/dungeon_map_parser.gd")
const SCREEN := preload("res://scenes/dev/scenario_select.tscn")

var _fails: Array[String] = []


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  OK   %s" % label)
	else:
		print("  FAIL %s" % label)
		_fails.append(label)


func _ready() -> void:
	await get_tree().process_frame
	_check_real_dungeons()
	await _check_tabs()
	if _fails.is_empty():
		print("All checks pass.")
		get_tree().quit(0)
	else:
		print("%d check(s) failed." % _fails.size())
		get_tree().quit(1)


func _check_real_dungeons() -> void:
	var ids: Array = []
	for config in ScenarioCatalog.real_dungeons():
		ids.append(config.id)
	_check(not ids.has(&"dev_rivals"), "a dungeon a scenario runs under is not a real dungeon")
	_check(GameData.dungeon(&"dev_rivals") != null, "...though GameData still holds it")
	_check(
		ScenarioCatalog.real_dungeon_ids().has(&"norgzevod_frozen_lake"),
		"a folder of maps is a real dungeon, with no DungeonConfig"
	)
	var owned := 0
	for scenario in ScenarioCatalog.list():
		if scenario.dungeon != null:
			owned += 1
	_check(
		ids.size() + owned == GameData.all_dungeons().size(),
		"every dungeon is either a scenario's or a real one"
	)


func _check_tabs() -> void:
	var screen := SCREEN.instantiate()
	add_child(screen)
	await get_tree().process_frame
	var tabs := _find_tabs(screen)
	_check(tabs != null, "the screen has a tab container")
	if tabs == null:
		return
	_check(tabs.get_tab_count() == 2, "two tabs")
	_check(tabs.get_tab_title(0) == tr("UI_DEV_TAB_SCENARIOS"), "first tab: scenarios")
	_check(tabs.get_tab_title(1) == tr("UI_DEV_TAB_DUNGEONS"), "second tab: dungeons")
	_check(tabs.get_tab_title(1) != "UI_DEV_TAB_DUNGEONS", "...and its title is translated")
	var buttons := 0
	for b in tabs.get_child(0).find_children("*", "Button", true, false):
		buttons += 1
	_check(buttons == ScenarioCatalog.list().size(), "one button per test scenario")
	var play: Array = []
	var edit: Array = []
	var make: Array = []
	for b in tabs.get_child(1).find_children("*", "Button", true, false):
		match b.get_meta("role", ""):
			"play":
				play.append(b)
			"edit":
				edit.append(b)
			"new":
				make.append(b)
	_check(
		play.size() == ScenarioCatalog.real_dungeon_ids().size(), "one play button per real dungeon"
	)
	for b in play:
		_check(
			b.text != "DUNGEON_NORGZEVOD_FROZEN_LAKE_NAME", "...with a translated name: %s" % b.text
		)
		_check(
			b.disabled != (b.pressed.get_connections().size() == 1),
			"...enabled and wired when it has maps, greyed out when not"
		)
	_check(
		edit.size() == MapParser.slugs().size(),
		"an Edit button for each dungeon with maps, and only those"
	)
	for b in edit:
		_check(
			b.text == tr("UI_DEV_DUNGEON_EDIT") and b.text != "UI_DEV_DUNGEON_EDIT", "...translated"
		)
		_check(b.pressed.get_connections().size() == 1, "...and wired")
		_check(not b.disabled, "...and enabled")
	_check(
		edit.size() > 0 and edit[0].get_parent().get_child(0).get_meta("role") == "play",
		"the Edit button sits beside the dungeon's own button"
	)
	_check(make.size() == 1, "one New dungeon button")
	_check(
		(
			make.size() == 1
			and make[0].text == tr("UI_DEV_DUNGEON_NEW")
			and make[0].text != "UI_DEV_DUNGEON_NEW"
		),
		"...translated"
	)
	if make.size() == 1:
		make[0].pressed.emit()
		await get_tree().process_frame
		var dialog: ConfirmationDialog = screen.get_node_or_null("NewDungeonDialog")
		_check(dialog != null, "it asks for a name")
		if dialog != null:
			var field: LineEdit = dialog.find_child("SlugField", true, false)
			_check(dialog.get_ok_button().disabled, "...and refuses an empty one")
			field.text = "Bad Name"
			field.text_changed.emit(field.text)
			_check(dialog.get_ok_button().disabled, "...a name with capitals or spaces")
			field.text = "norgzevod_frozen_lake"
			field.text_changed.emit(field.text)
			_check(dialog.get_ok_button().disabled, "...and one that is taken")
			field.text = "a_fresh_one"
			field.text_changed.emit(field.text)
			_check(not dialog.get_ok_button().disabled, "...and accepts a good one")
			dialog.queue_free()
	var verdicts := 0
	for label in tabs.get_child(1).find_children("*", "Label", true, false):
		if label.text.begins_with(tr("UI_DEV_DUNGEON_VERDICT").split("%")[0]):
			verdicts += 1
	_check(
		verdicts == MapParser.slugs().size(), "each dungeon with maps shows the validator's verdict"
	)
	screen.queue_free()


func _find_tabs(node: Node) -> TabContainer:
	var found := node.find_children("*", "TabContainer", true, false)
	return found[0] if not found.is_empty() else null
