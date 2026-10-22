## Headless check of the abilities that were `@unimplemented` and whose mechanic the design doc
## actually states. Only Fog Mantel qualifies: it is an exploration ability, implemented in
## `scripts/exploration/abilities/impl/fog_mantel.gd`, and its encounter-side script was a stale
## placeholder. Flow State and Self-Sabotage have no mechanic in the doc and stay unimplemented.
##
## Run with: Godot --headless --path . res://scenes/dev/unimplemented_b_check.tscn
## As a start scene rather than --script; see geometry_check.gd.
extends Node

const ScenarioCatalog := preload("res://scripts/dev/scenario_catalog.gd")
const EXPLORATION := preload("res://scenes/exploration/exploration.tscn")
const ExplorationContext := preload("res://scripts/exploration/abilities/exploration_context.gd")
const ExplorationAbilityCatalog := preload(
	"res://scripts/exploration/abilities/exploration_ability_catalog.gd"
)

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
	await _check_fog_mantel()
	_check_markers()
	print("")
	if _fails.is_empty():
		print("ALL OK")
	else:
		print("FAILURES: %s" % [_fails])
	get_tree().quit(0 if _fails.is_empty() else 1)


func _check_fog_mantel() -> void:
	print("[Fog Mantel]")
	ScenarioCatalog.selected_id = &"gates"
	var scene = EXPLORATION.instantiate()
	get_tree().root.add_child(scene)
	await get_tree().process_frame
	var dm = scene.get_node("DungeonManager")
	var player = scene.get_node("Player")
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261022
	var ability = ExplorationAbilityCatalog.script_for(&"fog_mantel")
	_check(not dm.rivals_ignore_player(), "visible to the rivals before it is used")

	var seen := {}
	for i in 60:
		player.clear_hidden()
		var ctx := ExplorationContext.new(dm, player, rng)
		if not ability.use(ctx):
			seen[-1] = true
		seen[player.invisible_moves] = true
	_check(not seen.has(-1), "using it always succeeds")
	var lo: int = seen.keys().min()
	var hi: int = seen.keys().max()
	_check(lo >= 5 and hi <= 8, "5 to 8 tiles (saw %d to %d)" % [lo, hi])
	_check(seen.size() > 1, "the number is rolled anew on each use")
	_check(dm.rivals_ignore_player(), "the rivals ignore the player while it lasts")

	player.clear_hidden()
	player.invisible_moves = 2
	player._tick_hidden_on_move()
	_check(dm.rivals_ignore_player(), "still hidden after one of two tiles")
	player._tick_hidden_on_move()
	_check(not dm.rivals_ignore_player(), "visible again once the tiles are walked")

	# A trap (clear_invisibility) or an encounter (clear_hidden) ends it at once.
	player.set_invisible(8)
	player.clear_invisibility()
	_check(not dm.rivals_ignore_player(), "a sprung trap ends it immediately")
	player.set_invisible(8)
	player.clear_hidden()
	_check(not dm.rivals_ignore_player(), "an encounter ends it immediately")

	# Not touched: another stealth state is not what a trap breaks.
	player.set_unpursued(5)
	player.set_invisible(5)
	player.clear_invisibility()
	_check(player.unpursued_moves == 5, "a trap leaves not-chased alone")

	scene.queue_free()
	await get_tree().process_frame


func _check_markers() -> void:
	print("[placeholders]")
	var dir := "res://scripts/encounter/effects/abilities/"
	for id in ["fog_mantel", "flow_state", "self_sabotage"]:
		var first := FileAccess.get_file_as_string(dir + id + ".gd").split("\n")[0]
		var marked := first.strip_edges() == "# @unimplemented"
		_check(marked == (id != "fog_mantel"), "%s: marker matches the state of its mechanic" % id)
