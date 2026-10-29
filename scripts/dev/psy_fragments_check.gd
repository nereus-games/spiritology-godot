## Headless check of the PSY ladder's encyclopaedia consequences: above PSY 20 a damaged fragment
## is likelier to be destroyed and a temporary oddity (swapped icons) may begin; above PSY 30 each
## batch of fragments brings one more parasitic fragment; above PSY 40 a poisoned player cannot
## open the encyclopaedia.
##
## Run with: Godot --headless --path . res://scenes/dev/psy_fragments_check.tscn
## As a start scene rather than --script; see geometry_check.gd.
extends Node

const Desk := preload("res://scripts/encyclopaedia/puzzle_desk.gd")
const GridLogic := preload("res://scripts/ui/encyclopaedia_grid_logic.gd")
const Screen := preload("res://scripts/ui/encyclopaedia_screen.gd")
const SPECIES := &"kalilk"

var _fails: Array[String] = []


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
	_check_parasites()
	_check_destruction()
	_check_oddities()
	_check_swap_cells()
	await _check_view_refusal()
	GameSession.reset()
	print("")
	if _fails.is_empty():
		print("ALL OK")
	else:
		print("FAILURES: %s" % [_fails])
	get_tree().quit(0 if _fails.is_empty() else 1)


func _check_parasites() -> void:
	print("parasitic fragments")
	for psy in [0, 30, 31]:
		GameSession.reset()
		GameSession.psy_score = psy
		GameSession.add_ifp(SPECIES, 2)
		_check(GameSession.parasitic_fragments(SPECIES) == 0, "PSY %d: no batch, no parasite" % psy)
		GameSession.add_ifp(SPECIES, 1)
		var expected := 2 if psy > 30 else 1
		_check(
			GameSession.true_fragments(SPECIES) == 1,
			"PSY %d: one true fragment" % psy
		)
		_check(
			GameSession.parasitic_fragments(SPECIES) == expected,
			"PSY %d: %d parasitic" % [psy, expected]
		)
		GameSession.add_ifp(SPECIES, 6)
		_check(
			GameSession.parasitic_fragments(SPECIES) == expected + 2 + (1 if psy > 30 else 0),
			"PSY %d: one extra per batch, not per fragment" % psy
		)


func _check_destruction() -> void:
	print("destruction risk")
	for psy in [20, 21]:
		GameSession.reset()
		GameSession.psy_score = psy
		var desk := Desk.new(Vector2i(24, 16), 4, 7)
		desk.balance = BalanceData.current().duplicate() as BalanceData
		desk.balance.puzzle_destroy_chance = 0.0
		var live := BalanceData.current()
		var saved := live.psy_destroy_bonus
		live.psy_destroy_bonus = 1.0
		desk.destroy_bonus = GameSession.psy_destroy_bonus()
		live.psy_destroy_bonus = saved
		desk.add_correct(0, Vector2i(0, 0), PackedInt32Array([1, 7, 2, 3]))
		desk.add_correct(1, Vector2i(1, 0), PackedInt32Array([4, 9, 5, 56]))
		desk.add_correct(2, Vector2i(2, 0), PackedInt32Array([8, 10, 12, 56]))
		desk.place(0, Vector2i(2, 2))
		desk.place(2, Vector2i(9, 2))
		var destroyed := false
		for _i in 2:
			desk.move(2, Vector2i.LEFT)
		var r = desk.move(2, Vector2i.LEFT)
		for snap in r.snaps:
			destroyed = destroyed or not snap.destroyed.is_empty()
		_check(destroyed == (psy > 20), "PSY %d: damaged fragment destroyed = %s" % [psy, psy > 20])


func _check_oddities() -> void:
	print("oddities")
	GameSession.reset()
	var balance := BalanceData.current()
	GameSession.oddity_rng.seed = 1
	var saved := balance.psy_oddity_chance
	balance.psy_oddity_chance = 1.0
	GameSession.psy_score = 20
	GameSession.register_encounter_end(false)
	_check(GameSession.active_oddity == &"", "PSY 20: no oddity")
	GameSession.psy_score = 21
	GameSession.register_encounter_end(false)
	_check(GameSession.oddity_active(&"swapped_icons"), "PSY 21: an oddity begins")
	for _i in balance.psy_oddity_encounters - 1:
		GameSession.register_encounter_end(false)
	_check(GameSession.oddity_active(&"swapped_icons"), "it lasts its encounters")
	GameSession.register_encounter_end(false)
	_check(GameSession.active_oddity == &"", "then it ends: temporary")
	GameSession.register_encounter_end(false)
	GameSession.reset()
	_check(GameSession.active_oddity == &"", "a new game starts clean")
	balance.psy_oddity_chance = saved


func _check_swap_cells() -> void:
	print("swapped icons")
	_check(GridLogic.swapped_icon_cell(0, 5) == 1 and GridLogic.swapped_icon_cell(1, 5) == 0, "pair")
	_check(GridLogic.swapped_icon_cell(3, 5) == 2, "second pair")
	_check(GridLogic.swapped_icon_cell(4, 5) == 4, "a last cell with no partner keeps its own")


func _check_view_refusal() -> void:
	print("poison and the encyclopaedia")
	for case in [[40, true, false], [41, false, false], [41, true, true]]:
		GameSession.psy_score = case[0]
		var screen := Screen.new()
		screen.poisoned = case[1]
		add_child(screen)
		await get_tree().process_frame
		_check(
			screen.is_forbidden() == case[2],
			"PSY %d, poisoned %s: forbidden %s" % [case[0], case[1], case[2]]
		)
		_check(
			(screen._grid == null) == case[2],
			"PSY %d, poisoned %s: grid shown only if allowed" % [case[0], case[1]]
		)
		screen.queue_free()
		await get_tree().process_frame
