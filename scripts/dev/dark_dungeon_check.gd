## Headless check of "In the Dark": a dungeon flagged dark, or any dungeon above PSY 40, limits
## sight to one tile; rivals beyond it are heard but not seen; Meditate shows them for 2 moves;
## and a lit area (what an NPC quest would trigger) is fully seen.
##
## Run with: Godot --headless --path . res://scenes/dev/dark_dungeon_check.tscn
## As a start scene rather than --script; see geometry_check.gd.
extends Node

const ScenarioCatalog := preload("res://scripts/dev/scenario_catalog.gd")
const EXPLORATION := preload("res://scenes/exploration/exploration.tscn")
const RIVAL_SCENE := preload("res://scenes/exploration/rival/rival.tscn")
const ExtraActions := preload("res://scripts/exploration/exploration_extra_actions.gd")
const ExplorationContext := preload("res://scripts/exploration/abilities/exploration_context.gd")
const DungeonSight := preload("res://scripts/exploration/dungeon_sight.gd")

## The "movement" scenario is an open room; the player enters at its north edge.
const START := Vector3i(3, 0, 0)
const NEAR := Vector3i(3, 0, 1)  # one tile from the player: seen
const HEARD := Vector3i(3, 0, 3)  # three tiles: heard, not seen, to the south
const FAR := Vector3i(0, 0, 8)  # eleven tiles: neither

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
	ScenarioCatalog.selected_id = &"movement"
	var scene = EXPLORATION.instantiate()
	get_tree().root.add_child(scene)
	await get_tree().process_frame
	var dm = scene.get_node("DungeonManager")
	var player = scene.get_node("Player")
	var sight = dm.sight
	GameSession.psy_score = 0
	player.teleport_to(START)
	for r in dm.rivals():
		r.remove_from_dungeon()
	await get_tree().process_frame
	var near = await _rival(dm, NEAR)
	var heard = await _rival(dm, HEARD)
	var far = await _rival(dm, FAR)
	var messages: Array[String] = []
	dm.message_posted.connect(func(text): messages.append(text))

	print("[A lit dungeon]")
	_check(not sight.is_dark(), "no config, PSY 0: not dark")
	dm.refresh_sight()
	_check(near.visible and heard.visible and far.visible, "every rival is drawn")
	_check(sight.tile_visible(FAR), "every tile is visible")
	_check(not sight.rival_heard(heard), "nothing is merely heard")

	print("[The config flag]")
	dm.config = DungeonConfig.new()
	_check(not sight.is_dark(), "a config without the flag is not dark")
	dm.config.dark = true
	_check(sight.is_dark(), "a config with the flag is dark")
	dm.refresh_sight()
	_check(near.visible, "the rival one tile away is seen")
	_check(not heard.visible and not far.visible, "the farther rivals are not drawn")
	_check(sight.tile_visible(START) and sight.tile_visible(NEAR), "own tile and neighbour seen")
	_check(not sight.tile_visible(HEARD), "a tile three away is not seen")
	_check(not sight.tile_visible(START + Vector3i(0, 1, 0)), "another floor is not seen")
	_check(sight.rival_heard(heard), "the rival three tiles away is heard")
	_check(not sight.rival_heard(far), "the rival eleven tiles away is not")
	_check(not sight.rival_heard(near), "a rival that is seen is not merely heard")

	print("[The heard cue]")
	var line: String = sight.heard_message()
	_check(line != "" and line != "UI_DARK_HEARD", "a cue is produced, translated: %s" % line)
	_check(
		line.contains(DungeonSight.direction_name(Vector3i(0, 0, 3))),
		"it names the direction of the rival (south)"
	)
	_check(sight.heard_message() == "", "it is not repeated while the rival stays audible")
	_check(DungeonSight.direction_name(Vector3i(-3, 0, 1)) != DungeonSight.direction_name(Vector3i(3, 0, 1)), "west is not east")
	_check(DungeonSight.direction_name(Vector3i(0, 0, -2)) != DungeonSight.direction_name(Vector3i(0, 0, 2)), "north is not south")

	print("[The cue through the turn model]")
	sight._was_heard = {}
	messages.clear()
	dm.advance_turn()
	_check(messages.size() == 1, "advancing a turn posts the cue once (%d)" % messages.size())
	dm.advance_turn()
	_check(messages.size() == 1, "and not again on the next turn")

	print("[Meditate]")
	var balance := BalanceData.current()
	_check(balance.dark_reveal_moves == 2, "the reveal lasts 2 moves")
	var extra = ExtraActions.new(ExplorationContext.new(dm, player))
	for a in extra.combine(dm.actions_for(player.tile, player.facing_delta(), player)):
		if a.id == &"meditate":
			a.callable.call()
	_check(far.visible and heard.visible, "Meditate shows every rival")
	dm.advance_turn()
	_check(far.visible, "still shown after the first move")
	dm.advance_turn()
	_check(not far.visible and not heard.visible, "hidden again after the second move")
	_check(near.visible, "the near rival stays seen")

	print("[PSY above 40]")
	GameSession.psy_score = 41
	_check(sight.is_dark(), "above PSY 40 any dungeon is dark")
	dm.config.dark = false
	_check(sight.is_dark(), "even when the config is not")
	GameSession.psy_score = 40
	_check(not sight.is_dark(), "PSY 40 itself is not above rung 4")
	dm.config.dark = true

	print("[Light]")
	var changes := [0]
	sight.lit_changed.connect(func(): changes[0] += 1)
	_check(not sight.is_lit(FAR), "the far tile starts unlit")
	sight.light_radius(HEARD, 1)
	_check(changes[0] == 1, "lighting emits lit_changed once")
	_check(sight.is_lit(HEARD) and sight.is_lit(HEARD + Vector3i(0, 0, 1)), "the radius is lit")
	_check(not sight.is_lit(HEARD + Vector3i(2, 0, 0)), "not beyond the radius")
	dm.refresh_sight()
	_check(heard.visible, "a rival on a lit tile is seen from afar")
	_check(not far.visible, "an unlit one is not")
	_check(not sight.rival_heard(heard), "a rival in the light is not merely heard")
	sight.light_radius(HEARD, 1)
	_check(changes[0] == 1, "lighting what is lit changes nothing")
	sight.light_box(Vector3i(0, 0, 7), Vector3i(1, 0, 8))
	_check(sight.is_lit(FAR), "a box can be lit")
	dm.refresh_sight()
	_check(far.visible, "so the rival in it is seen")
	sight.clear_light()
	dm.refresh_sight()
	_check(not sight.is_lit(HEARD) and not heard.visible, "putting the light out darkens it again")

	print("[Back to a lit dungeon]")
	dm.config.dark = false
	dm.refresh_sight()
	_check(near.visible and heard.visible and far.visible, "a lit dungeon shows everyone")

	GameSession.psy_score = 0
	print("")
	if _fails.is_empty():
		print("ALL OK")
	else:
		print("FAILURES: %s" % [_fails])
	scene.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if _fails.is_empty() else 1)


## A rival that stays where it is put.
func _rival(dm, tile: Vector3i) -> Node:
	var r = RIVAL_SCENE.instantiate()
	r.position = dm.tile_to_world(tile)
	dm.add_child(r)
	await get_tree().process_frame
	r.rest(9999)
	return r
