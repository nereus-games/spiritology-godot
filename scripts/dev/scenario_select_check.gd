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
	var dungeon_buttons := tabs.get_child(1).find_children("*", "Button", true, false)
	_check(
		dungeon_buttons.size() == ScenarioCatalog.real_dungeon_ids().size(),
		"one button per real dungeon"
	)
	for b in dungeon_buttons:
		_check(b.disabled, "...greyed out: %s" % b.text)
		_check(b.text != "DUNGEON_NORGZEVOD_FROZEN_LAKE_NAME", "...with a translated name")
	var verdicts := 0
	for label in tabs.get_child(1).find_children("*", "Label", true, false):
		if label.text.begins_with(tr("UI_DEV_DUNGEON_VERDICT").split("%")[0]):
			verdicts += 1
	_check(verdicts == MapParser.slugs().size(), "each dungeon with maps shows the validator's verdict")
	screen.queue_free()


func _find_tabs(node: Node) -> TabContainer:
	var found := node.find_children("*", "TabContainer", true, false)
	return found[0] if not found.is_empty() else null
