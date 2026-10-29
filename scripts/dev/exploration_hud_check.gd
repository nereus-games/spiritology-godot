## Headless check of the exploration HUD's logic: the stack of known abilities with its USE /
## CANCEL submenu (which abilities are listed, which are usable, the flow, a spent ability staying
## greyed), the "Abilities" entry of the action menu, and the encyclopaedia notices that reach the
## HUD's banner one at a time.
##
## Run with: Godot --headless --path . res://scenes/dev/exploration_hud_check.tscn
## As a start scene rather than --script; see geometry_check.gd.
extends Node

const AbilityStack := preload("res://scripts/exploration/exploration_ability_stack.gd")
const Catalog := preload("res://scripts/exploration/abilities/exploration_ability_catalog.gd")
const ExtraActions := preload("res://scripts/exploration/exploration_extra_actions.gd")
const ExplorationContext := preload("res://scripts/exploration/abilities/exploration_context.gd")
const Notices := preload("res://scripts/ui/encyclopaedia_notices.gd")
const HUD := preload("res://ui/hud_exploration.tscn")

var _fails: Array[String] = []


class FakeScouting:
	extends RefCounted
	var active := false


class FakeDungeon:
	extends Node
	var messages: Array[String] = []
	var scouting := FakeScouting.new()

	func post_message(text: String) -> void:
		messages.append(text)


class FakePlayer:
	extends Node


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  OK   %s" % label)
	else:
		print("  FAIL %s" % label)
		_fails.append(label)


func _ready() -> void:
	_run_all()


func _run_all() -> void:
	await get_tree().process_frame
	TranslationServer.set_locale("en")  # the lines are compared in English
	_check_stack()
	_check_entry()
	_check_notices()
	await _check_hud()
	print("")
	if _fails.is_empty():
		print("ALL OK")
	else:
		print("FAILURES: %s" % [_fails])
	Catalog.dev_granted = []
	get_tree().quit(0 if _fails.is_empty() else 1)


func _fresh() -> Dictionary:
	GameSession.reset()
	GameSession.main_character = &""
	GameSession.teammate = &""
	Catalog.dev_granted = [&"fog_mantel", &"static_camouflage"]
	var dungeon := FakeDungeon.new()
	var player := FakePlayer.new()
	add_child(dungeon)
	add_child(player)
	var ctx := ExplorationContext.new(dungeon, player)
	return {"dungeon": dungeon, "player": player, "ctx": ctx, "stack": AbilityStack.new(ctx)}


func _free(world: Dictionary) -> void:
	world.dungeon.free()
	world.player.free()


func _check_stack() -> void:
	print("[The stack]")
	var w := _fresh()
	var stack = w.stack
	var ids: Array = []
	for e in stack.entries():
		ids.append(e.id)
	_check(ids == [&"fog_mantel", &"static_camouflage"], "known abilities are listed (%s)" % [ids])
	_check(not stack.is_open(), "closed to begin with")
	_check(stack.open() and stack.mode == AbilityStack.Mode.STACK, "opens on the stack")
	_check(stack.selected_id() == &"fog_mantel", "the cursor starts on the first")
	stack.move(1)
	_check(stack.selected_id() == &"static_camouflage", "moving goes down")
	stack.move(1)
	_check(stack.selected_id() == &"fog_mantel", "...and wraps")
	stack.move(-1)
	_check(stack.selected_id() == &"static_camouflage", "...both ways")
	stack.move(-1)

	print("[Submenu: CANCEL goes back]")
	stack.accept()
	_check(stack.mode == AbilityStack.Mode.SUBMENU, "accept opens the submenu")
	var opts: Array = stack.submenu_options()
	_check(
		opts[0].id == &"use" and opts[1].id == &"cancel" and opts[0].enabled,
		"USE then CANCEL, USE enabled"
	)
	_check(stack.submenu_index() == 0, "the cursor starts on USE")
	stack.move(1)
	stack.accept()
	_check(stack.mode == AbilityStack.Mode.STACK, "CANCEL returns to the stack")
	_check(not GameSession.is_exploration_ability_used(&"fog_mantel"), "...using nothing")
	stack.back()
	_check(not stack.is_open(), "back from the stack closes it")

	print("[Submenu: USE]")
	stack.open()
	stack.accept()
	var used: bool = stack.accept()
	_check(used, "USE reports the ability used")
	_check(GameSession.is_exploration_ability_used(&"fog_mantel"), "...and marks it spent")
	_check(not stack.is_open(), "...and closes the stack")
	_check(not w.ctx.log.is_empty(), "the effect ran (%s)" % [w.ctx.log])

	print("[A spent ability stays listed, greyed]")
	var spent_entry: Dictionary = stack.entries()[0]
	_check(
		spent_entry.id == &"fog_mantel" and not spent_entry.usable,
		"fog_mantel is listed and not usable"
	)
	_check(spent_entry.reason_key == "UI_ABILITY_SPENT", "...with the reason")
	stack.open()
	stack.accept()
	_check(
		not stack.submenu_options()[0].enabled and stack.submenu_index() == 1,
		"USE is greyed and the cursor starts on CANCEL"
	)
	stack.move(-1)
	_check(not stack.accept() and w.dungeon.messages.size() == 1, "forcing USE posts the reason")
	_check(stack.is_open(), "...and stays open")
	_check(
		w.dungeon.messages[0] == TranslationServer.translate("UI_ABILITY_SPENT"),
		"...translated, not a key"
	)
	stack.close()

	print("[Refreshed]")
	GameSession.refresh_all_exploration_abilities()
	_check(stack.entries()[0].usable, "a refresh crystal makes it usable again")

	print("[A running watch blocks every use]")
	w.dungeon.scouting.active = true
	for e in stack.entries():
		_check(not e.usable and e.reason_key == "UI_ABILITY_BUSY", "%s is busy" % e.id)
	w.dungeon.scouting.active = false

	print("[No ability known]")
	Catalog.dev_granted = []
	_check(not stack.has_abilities() and not stack.open(), "nothing to open")
	_free(w)


func _check_entry() -> void:
	print("[The Abilities entry of the action menu]")
	var w := _fresh()
	var extra = ExtraActions.new(w.ctx)
	var ids: Array = []
	for a in extra.build():
		ids.append(a.id)
	_check(&"abilities" in ids, "offered while abilities are known (%s)" % [ids])
	_check(not (&"fog_mantel" in ids), "abilities are no longer listed one by one")
	for a in extra.build():
		if a.id == &"abilities":
			a.callable.call()
	_check(extra.stack.is_open(), "choosing it opens the stack")
	Catalog.dev_granted = []
	ids.clear()
	for a in extra.build():
		ids.append(a.id)
	_check(not (&"abilities" in ids), "absent when none is known")
	_free(w)


func _check_notices() -> void:
	print("[Encyclopaedia notices]")
	GameSession.reset()
	var notices = Notices.new()
	notices.connect_session()
	GameSession.add_ifp(&"gelmi", 3)
	_check(notices.has_pending(), "forming fragments is announced")
	var line: String = notices.take()
	_check(not line.contains("NOTICE_") and line.contains(TranslationServer.translate("SPECIES_GELMI_NAME")), "...translated: %s" % line)
	GameSession.encyclopaedia_progress.emit(&"gelmi", 5)
	GameSession.encyclopaedia_page_changed.emit(&"gelmi", false)
	_check(not notices.has_pending(), "progress and page changes are not announced")
	GameSession.encyclopaedia_ability_unlocked.emit(&"gelmi", &"fog_mantel")
	GameSession.encyclopaedia_page_assembled.emit(&"gelmi", false)
	GameSession.encyclopaedia_page_assembled.emit(&"gelmi", true)
	_check(notices.pending.size() == 3, "an unlock and two assemblies queue three lines")
	_check(notices.take().contains("Fog Mantel"), "first in, first out")
	for l in notices.pending:
		_check(not l.contains("NOTICE_"), "translated: %s" % l)
	notices.disconnect_session()
	notices.pending.clear()
	GameSession.encyclopaedia_page_assembled.emit(&"gelmi", false)
	_check(not notices.has_pending(), "silent once disconnected")


func _check_hud() -> void:
	print("[The HUD's banner]")
	GameSession.reset()
	var hud = HUD.instantiate()
	add_child(hud)
	await get_tree().process_frame
	GameSession.encyclopaedia_page_assembled.emit(&"gelmi", true)
	GameSession.encyclopaedia_page_assembled.emit(&"gelmi", false)
	hud._pump_notices(0.1)
	var first: String = hud._message_label.text
	_check(first.contains("Forlorn") and hud._message_label.modulate.a == 1.0, "first notice shown")
	hud._pump_notices(1.0)
	_check(hud._message_label.text == first, "the second waits for the first to be read")
	hud._pump_notices(hud.MESSAGE_HOLD)
	_check(hud._message_label.text != first, "...then replaces it")
	hud.queue_free()
	await get_tree().process_frame
