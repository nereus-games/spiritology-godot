## Headless check of the dev selection screen's two tabs: test scenarios, and real dungeons.
## A dungeon that a scenario runs under is a test fixture and belongs to the first tab only.
##
## Run with: Godot --headless --path . res://scenes/dev/scenario_select_check.tscn
## As a start scene rather than --script; see geometry_check.gd.
extends Node

const ScenarioCatalog := preload("res://scripts/dev/scenario_catalog.gd")
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
	if ScenarioCatalog.real_dungeons().is_empty():
		var labels := tabs.get_child(1).find_children("*", "Label", true, false)
		_check(
			labels.size() == 1 and labels[0].text == tr("UI_DEV_DUNGEONS_EMPTY"),
			"no real dungeon: the tab says so"
		)
	screen.queue_free()


func _find_tabs(node: Node) -> TabContainer:
	var found := node.find_children("*", "TabContainer", true, false)
	return found[0] if not found.is_empty() else null
