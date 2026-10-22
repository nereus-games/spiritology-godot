## Headless check of PSY ladder rungs 3 and 4: the rival's density hidden in the encounter's turn
## order (and Talk's reduced IFP), rivals losing their cooldown turn on the map, and poison
## forbidding Meditate and objects, with a warning, in an encounter and in exploration.
##
## Run with: Godot --headless --path . res://scenes/dev/psy_rungs_check.tscn
## As a start scene rather than --script; see geometry_check.gd.
extends Node

const ENCOUNTER := preload("res://scenes/encounter/encounter.tscn")
const RivalBehaviorScript := preload("res://scripts/exploration/rival_behavior.gd")
const ExtraActions := preload("res://scripts/exploration/exploration_extra_actions.gd")
const ExplorationContext := preload("res://scripts/exploration/abilities/exploration_context.gd")
const AfflictionState := preload("res://scripts/exploration/mechanisms/affliction_state.gd")
const SEED := 20260909

var _fails: Array[String] = []


## Stands in for the player and the dungeon in exploration.
class FakePlayer:
	extends Node
	var affliction


class FakeDungeon:
	extends Node
	var messages: Array[String] = []

	func post_message(text: String) -> void:
		messages.append(text)


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
	_check_ladder()
	_check_talk_ifp()
	_check_rival_cooldown()
	_check_exploration()
	await _check_encounter()
	GameSession.psy_score = 0
	print("")
	if _fails.is_empty():
		print("ALL OK")
	else:
		print("FAILURES: %s" % [_fails])
	get_tree().quit(0 if _fails.is_empty() else 1)


func _check_ladder() -> void:
	print("[The ladder]")
	GameSession.psy_score = 40
	_check(GameSession.psy_above(3) and not GameSession.psy_above(4), "40 is above 3, not 4")
	GameSession.psy_score = 41
	_check(GameSession.psy_above(4), "41 is above 4")
	_check(GameSession.psy_forbids_while_poisoned(true), "41 poisoned forbids")
	_check(not GameSession.psy_forbids_while_poisoned(false), "41 not poisoned allows")
	GameSession.psy_score = 40
	_check(not GameSession.psy_forbids_while_poisoned(true), "40 poisoned allows")


func _check_talk_ifp() -> void:
	print("[Talk's IFP above rung 3]")
	GameSession.psy_score = 31
	var talk := GameEnums.IfpAction.TALK_RIVAL
	_check(GameSession.ifp_amount(talk, false) == 1, "ordinary Talk yields 1 IFP at PSY 31")
	_check(GameSession.ifp_amount(talk, true, true) == 2, "Forlorn Talk yields 2 IFP at PSY 31")
	GameSession.psy_score = 0
	_check(GameSession.ifp_amount(talk, false) == 2, "ordinary Talk yields 2 IFP at PSY 0")


func _check_rival_cooldown() -> void:
	print("[Rival cooldown]")
	var rival = RivalBehaviorScript.new()
	rival.turns_between_actions = 2
	GameSession.psy_score = 0
	var calm: Array[bool] = []
	for i in 4:
		calm.append(rival._acts_this_turn())
	_check(calm == [true, false, true, false], "acts every other turn at PSY 0 (%s)" % [calm])
	GameSession.psy_score = 41
	var reactive: Array[bool] = []
	for i in 4:
		reactive.append(rival._acts_this_turn())
	_check(reactive == [true, true, true, true], "acts every turn at PSY 41 (%s)" % [reactive])
	GameSession.psy_score = 40
	rival._cooldown = 0
	var edge: Array[bool] = [rival._acts_this_turn(), rival._acts_this_turn()]
	_check(edge == [true, false], "PSY 40 is not yet reactive (%s)" % [edge])
	rival.free()


func _check_exploration() -> void:
	print("[Poison in exploration]")
	var player := FakePlayer.new()
	var dungeon := FakeDungeon.new()
	player.affliction = AfflictionState.new()
	player.affliction.add_poison(3, 1)
	var extra = ExtraActions.new(ExplorationContext.new(dungeon, player))
	var warning := String(TranslationServer.translate("UI_PSY_POISON_FORBIDS"))
	_check(warning != "UI_PSY_POISON_FORBIDS", "the warning is translated")

	GameSession.set_eth(GameSession.PartySlot.MAIN, 10)
	GameSession.psy_score = 41
	extra._run_meditate(null)
	_check(GameSession.get_eth(GameSession.PartySlot.MAIN) == 10, "Meditate refused at PSY 41")
	_check(dungeon.messages == [warning], "the refusal posts the warning (%s)" % [dungeon.messages])
	extra._run_object(&"no_such_object")
	_check(dungeon.messages.size() == 2, "an object is refused too")

	GameSession.psy_score = 40
	extra._run_meditate(null)
	_check(GameSession.get_eth(GameSession.PartySlot.MAIN) > 10, "Meditate allowed at PSY 40")

	GameSession.psy_score = 41
	player.affliction.cure_poison()
	GameSession.set_eth(GameSession.PartySlot.MAIN, 10)
	extra._run_meditate(null)
	_check(GameSession.get_eth(GameSession.PartySlot.MAIN) > 10, "Meditate allowed unpoisoned")
	player.free()
	dungeon.free()


func _check_encounter() -> void:
	print("[The encounter screen]")
	GameSession.add_ifp(&"ravbak", 10)
	GameSession.psy_score = 0
	var ui := ENCOUNTER.instantiate()
	get_tree().root.add_child(ui)
	ui.begin(["kalilk", "fliritus"], ["ravbak"], {}, [], SEED)
	for _i in 20:
		await get_tree().process_frame
	# Debug builds open with the debug view on, which lifts every veil: turn it off.
	ui._debug_view = false
	ui._apply_debug_view()
	ui._refresh_timeline()
	_check(_rival_den_text(ui) != "", "a known rival's DEN is shown at PSY 0")
	_check(_player_den_text(ui) != "", "a player's DEN is shown at PSY 0")
	GameSession.psy_score = 31
	ui._refresh_timeline()
	_check(_rival_den_text(ui) == "", "a known rival's DEN is hidden at PSY 31")
	_check(_player_den_text(ui) != "", "a player's DEN stays shown at PSY 31")
	GameSession.psy_score = 30
	ui._refresh_timeline()
	_check(_rival_den_text(ui) != "", "a rival's DEN is shown at PSY 30")

	var meditate := _bar_button(ui, "UI_ENCOUNTER_ACTION_MEDITATE")
	var objects := _bar_button(ui, "UI_ENCOUNTER_ACTION_OBJECT")
	_check(meditate != null and objects != null, "the player is choosing an action")
	if meditate == null or objects == null:
		ui.queue_free()
		return
	var warning := String(TranslationServer.translate("UI_PSY_POISON_FORBIDS"))
	GameSession.inventory[&"check_object"] = 1
	objects.disabled = false
	ui.player_poisoned = true
	GameSession.psy_score = 41
	ui._description.text = ""
	objects.pressed.emit()
	_check(ui._description.text == warning, "Objects refused with a warning at PSY 41")
	_check(_bar_button(ui, "UI_ENCOUNTER_ACTION_OBJECT") == objects, "the menu did not move on")
	ui._description.text = ""
	meditate.pressed.emit()
	_check(ui._description.text == warning, "Meditate refused with a warning at PSY 41")
	_check(_bar_button(ui, "UI_ENCOUNTER_ACTION_MEDITATE") == meditate, "no turn was spent")
	GameSession.inventory.erase(&"check_object")
	GameSession.encyclopaedia = GameSession.EncyclopaediaModel.new()
	ui.queue_free()


func _timeline_entries(ui) -> Array:
	return ui._timeline_row.get_children().filter(func(c): return not c.is_queued_for_deletion())


func _rival_den_text(ui) -> String:
	return _den_of(ui, false)


func _player_den_text(ui) -> String:
	return _den_of(ui, true)


func _den_of(ui, player_side: bool) -> String:
	for e in _timeline_entries(ui):
		var is_player: bool = e._frame.get_theme_stylebox("panel").bg_color == e.COLOR_BG_PLAYER
		if is_player == player_side:
			return e._den_label.text
	return "<none>"


func _bar_button(ui, key: String) -> Button:
	var text := String(TranslationServer.translate(key)).to_upper()
	for b in ui._action_bar.get_children():
		if b is Button and not b.is_queued_for_deletion() and b.text == text:
			return b
	return null
