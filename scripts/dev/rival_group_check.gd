## Headless check on rival GROUPS and on the seam between the map and the encounter: a silhouette
## carries several individuals, damage on the map reaches each of them, the encounter hands back
## what it left of the group, and a duo that runs away lands a few steps off.
##
## Run with: Godot --headless --path . res://scenes/dev/rival_group_check.tscn
## As a start scene rather than --script; see geometry_check.gd.
extends Node

const ScenarioCatalog := preload("res://scripts/dev/scenario_catalog.gd")
const EXPLORATION := preload("res://scenes/exploration/exploration.tscn")
const ENCOUNTER := preload("res://scenes/encounter/encounter.tscn")
const RIVAL_SCENE := preload("res://scenes/exploration/rival/rival.tscn")
const RivalMember := preload("res://scripts/exploration/rival_member.gd")

## The "movement" scenario: an open 7 x 9 room with pillars, entered at (3, 0, 0).
const START := Vector3i(3, 0, 0)
const NEXT_TO_START := Vector3i(3, 0, 1)

## Runs of a flight, to see the group both vanish and stay. With a 50 % chance, all of them
## coming out the same way would take a 1 in 2^39 fluke.
const FLIGHTS := 40

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
	var ctx := await _setup()
	await _check_group(ctx)
	await _check_map_damage(ctx)
	await _check_encounter_report(ctx)
	await _check_rest(ctx)
	await _check_flight(ctx)
	_check_walking_distances(ctx)
	await _check_closing_key(ctx)
	await _check_encounter_states()
	# Last: leaving the dungeon changes scene, which frees the exploration scene. The timer lets
	# the fade and the change run their course before quitting.
	await _check_leaving_the_dungeon(ctx)
	await get_tree().create_timer(1.0).timeout
	print("")
	if _fails.is_empty():
		print("ALL OK")
	else:
		print("FAILURES: %s" % [_fails])
	get_tree().quit(0 if _fails.is_empty() else 1)


# --------------------------------------------------------------------------
# The test field
# --------------------------------------------------------------------------


func _setup() -> Dictionary:
	ScenarioCatalog.selected_id = &"movement"
	var scene = EXPLORATION.instantiate()
	get_tree().root.add_child(scene)
	await get_tree().process_frame
	return {
		"scene": scene, "dm": scene.get_node("DungeonManager"), "player": scene.get_node("Player")
	}


## A group on `tile`, one member per `[species, max_den, max_eth]`.
func _spawn_group(dm, tile: Vector3i, spec: Array) -> Node:
	var group = RIVAL_SCENE.instantiate()
	for s in spec:
		group.members.append(RivalMember.new(s[0], s[1], s[2]))
	group.position = dm.tile_to_world(tile)
	dm.add_child(group)
	await get_tree().process_frame
	return group


func _clear_rivals(dm) -> void:
	for r in dm.rivals():
		r.remove_from_dungeon()
	await get_tree().process_frame


func _report_entry(den: int, eth: int, outcome: StringName) -> Dictionary:
	return {"den": den, "eth": eth, "outcome": outcome}


# --------------------------------------------------------------------------
# A silhouette is a group
# --------------------------------------------------------------------------


func _check_group(ctx: Dictionary) -> void:
	print("[a silhouette is a group]")
	var dm = ctx.dm
	var g = await _spawn_group(
		dm, Vector3i(1, 0, 4), [[&"ravbak", 60, 40], [&"kalilk", 30, 20], [&"skorpis", 80, 50]]
	)
	_check(g.members.size() == 3, "three members")
	_check(g.species_id == &"ravbak", "the silhouette shows its first member (%s)" % g.species_id)
	_check(g.den == 30, "the group's DEN is its weakest member's (%d)" % g.den)
	_check(
		g.encounter_species() == [&"ravbak", &"kalilk", &"skorpis"],
		"the encounter gets every member, in order"
	)
	var states: Array = g.encounter_states()
	_check(
		states[1] == {"den": 30, "max_den": 30, "eth": 20, "max_eth": 20},
		"each with its own DEN and ETH (%s)" % [states[1]]
	)

	# The shorthand every hand-placed rival relies on: no members given, one built from the exports.
	var lone = RIVAL_SCENE.instantiate()
	lone.species_id = &"kalilk"
	lone.max_den = 70
	lone.position = dm.tile_to_world(Vector3i(5, 0, 4))
	dm.add_child(lone)
	await get_tree().process_frame
	_check(
		lone.members.size() == 1 and lone.members[0].species_id == &"kalilk",
		"a rival placed alone is a group of one"
	)
	_check(
		lone.den == 70 and lone.members[0].max_eth == BalanceData.current().base_eth,
		"with the DEN it was given and the base ETH"
	)
	await _clear_rivals(dm)


# --------------------------------------------------------------------------
# Damage on the map: everyone falls, everyone takes it
# --------------------------------------------------------------------------


func _check_map_damage(ctx: Dictionary) -> void:
	print("[damage on the map]")
	var dm = ctx.dm
	var g = await _spawn_group(
		dm, Vector3i(1, 0, 4), [[&"ravbak", 60, 40], [&"kalilk", 30, 20], [&"skorpis", 80, 50]]
	)
	_check(g.apply_map_damage(10), "a fall the group survives")
	_check(
		g.members.map(func(m): return m.den) == [50, 20, 70],
		"every member takes the whole of it (%s)" % [g.members.map(func(m): return m.den)]
	)
	_check(g.apply_map_damage(20), "a fall that dissolves one member only")
	_check(
		g.members.size() == 2, "the dissolved member leaves the group (%d left)" % g.members.size()
	)
	g.apply_map_damage(30)
	_check(
		g.members.size() == 1 and g.species_id == &"skorpis",
		"when the first member goes, the silhouette shows the next one (%s)" % g.species_id
	)
	_check(not g.apply_map_damage(100), "a fall that dissolves everyone")
	await get_tree().process_frame
	_check(not is_instance_valid(g) and dm.rivals().is_empty(), "the group leaves the dungeon")

	# Whether to jump after the player is weighed on the weakest member: 2 storeys cost 10 DEN.
	var sturdy = await _spawn_group(dm, Vector3i(1, 0, 4), [[&"ravbak", 100, 50]])
	var mixed = await _spawn_group(
		dm, Vector3i(5, 0, 4), [[&"ravbak", 100, 50], [&"kalilk", 8, 50]]
	)
	_check(sturdy.fall_pursuit_chance(2) > 0.0, "a sturdy group may jump")
	_check(
		mixed.fall_pursuit_chance(2) == 0.0, "a group never jumps if it would dissolve its weakest"
	)
	await _clear_rivals(dm)


# --------------------------------------------------------------------------
# Back from the encounter
# --------------------------------------------------------------------------


func _check_encounter_report(ctx: Dictionary) -> void:
	print("[back from the encounter]")
	var dm = ctx.dm
	var scene = ctx.scene
	var g = await _spawn_group(
		dm, Vector3i(1, 0, 4), [[&"ravbak", 60, 40], [&"kalilk", 30, 20], [&"skorpis", 80, 50]]
	)
	var report := [
		_report_entry(0, 10, &"dissolved"),
		_report_entry(12, 7, &"fled"),
		_report_entry(45, 30, &"pacified"),
	]
	_check(g.take_encounter_report(report), "a group with a member left survives")
	_check(
		g.members.size() == 1 and g.species_id == &"kalilk",
		"the dissolved and the pacified are gone, the one that fled stays"
	)
	_check(
		g.members[0].den == 12 and g.members[0].eth == 7,
		"with the DEN and ETH it fled with (%d / %d)" % [g.members[0].den, g.members[0].eth]
	)

	# The damage the encounter did is still there afterwards, whatever the outcome.
	var hurt = await _spawn_group(dm, Vector3i(5, 0, 4), [[&"ravbak", 60, 40]])
	scene._pending_rival = hurt
	scene._on_encounter_finished(&"defeat", [_report_entry(25, 18, &"stayed")])
	_check(
		is_instance_valid(hurt) and hurt.den == 25 and hurt.members[0].eth == 18,
		"after a defeat, the group keeps the damage it took (%d DEN)" % hurt.den
	)

	# Every member dissolved: the silhouette is gone.
	var beaten = await _spawn_group(
		dm, Vector3i(3, 0, 7), [[&"ravbak", 60, 40], [&"kalilk", 30, 20]]
	)
	scene._pending_rival = beaten
	scene._on_encounter_finished(
		&"victory", [_report_entry(0, 40, &"dissolved"), _report_entry(0, 20, &"dissolved")]
	)
	await get_tree().process_frame
	_check(not is_instance_valid(beaten), "after a victory, the group is gone")
	await _clear_rivals(dm)


# --------------------------------------------------------------------------
# A group that is still there does not start again at once
# --------------------------------------------------------------------------


func _check_rest(ctx: Dictionary) -> void:
	print("[resting after an encounter]")
	var dm = ctx.dm
	var scene = ctx.scene
	var player = ctx.player
	player.teleport_to(START)
	var g = await _spawn_group(dm, NEXT_TO_START, [[&"ravbak", 60, 40]])
	scene._pending_rival = g
	scene._on_encounter_finished(&"timeout", [_report_entry(40, 30, &"stayed")])
	var turns := BalanceData.current().rival_rest_turns
	_check(g.is_resting(), "the group rests after the encounter")
	var requested := [0]
	var on_request := func(_rival, _by_rival): requested[0] += 1
	dm.encounter_requested.connect(on_request)
	for i in turns:
		await g.take_turn(player.tile)
	_check(
		requested[0] == 0 and g.tile == NEXT_TO_START,
		"for %d turns it neither moves nor engages" % turns
	)
	_check(not g.is_resting(), "then it is back on its feet")
	dm.encounter_requested.disconnect(on_request)
	scene._pending_rival = null
	await _clear_rivals(dm)


# --------------------------------------------------------------------------
# Running away
# --------------------------------------------------------------------------


func _check_flight(ctx: Dictionary) -> void:
	print("[running away]")
	var dm = ctx.dm
	var scene = ctx.scene
	var player = ctx.player
	var balance := BalanceData.current()
	var vanished := 0
	var stayed := 0
	var off_range: Array = []
	for i in FLIGHTS:
		player.teleport_to(START)
		var g = await _spawn_group(dm, NEXT_TO_START, [[&"ravbak", 60, 40]])
		var steps: Dictionary = dm.walking_distances(START, balance.flee_distance_max)
		scene._pending_rival = g
		scene._on_encounter_finished(&"fled", [_report_entry(33, 20, &"stayed")])
		var walked: int = steps.get(player.tile, -1)
		if walked < balance.flee_distance_min or walked > balance.flee_distance_max:
			off_range.append("%s (%d steps)" % [player.tile, walked])
		await get_tree().process_frame
		if is_instance_valid(g):
			stayed += 1
			if not g.is_resting() or g.den != 33:
				off_range.append("a group left behind is not resting with its DEN")
			g.remove_from_dungeon()
			await get_tree().process_frame
		else:
			vanished += 1
	_check(
		off_range.is_empty(),
		(
			"the duo lands %d to %d walkable steps away%s"
			% [
				balance.flee_distance_min,
				balance.flee_distance_max,
				"" if off_range.is_empty() else " — " + ", ".join(off_range)
			]
		)
	)
	_check(
		vanished > 0 and stayed > 0,
		"the group is sometimes gone, sometimes not (%d gone, %d stayed)" % [vanished, stayed]
	)
	player.teleport_to(START)


## The key that closes the encounter screen must stop there. Exploration wakes up within the same
## event, and Space is its `interact` too: after a flight, on a tile offering nothing but MENU,
## the key went on to confirm it and the scenario was left for the picker.
func _check_closing_key(ctx: Dictionary) -> void:
	print("[closing the encounter screen]")
	var scene = ctx.scene
	var player = ctx.player
	var hud = scene.get_node("HudExploration")
	get_tree().current_scene = scene  # what TransitionManager pauses and wakes up
	player.teleport_to(START)
	TransitionManager.open_encounter([&"draka", &"kalilk"], [&"kalilk"], {}, [])
	var ui = TransitionManager._encounter
	await get_tree().process_frame
	var ui_menu_visible := [ui._menu_button.visible]
	# The encounter is over: the screen waits for a key to close.
	ui._result = &"fled"
	ui._rival_report = []
	ui._awaiting_close = true
	var key := InputEventKey.new()
	# Both codes: the engine's ui_accept matches the logical key, the project's `interact` the
	# physical one — which is exactly how one key press reaches both.
	key.keycode = KEY_SPACE
	key.physical_keycode = KEY_SPACE
	key.pressed = true
	Input.parse_input_event(key)
	await get_tree().process_frame
	var release := key.duplicate()
	release.pressed = false
	Input.parse_input_event(release)
	for i in 5:
		await get_tree().process_frame
	_check(TransitionManager._encounter == null, "Space closes the encounter screen")
	_check(
		hud._action_menu.selected_id() == &"menu",
		"the duo lands where MENU is the action on offer (%s)" % hud._action_menu.selected_id()
	)
	_check(
		is_instance_valid(scene) and TransitionManager._fade.modulate.a == 0.0,
		"and the same key does not go on to leave the scenario"
	)
	_check(not ui_menu_visible[0], "the encounter offers no shortcut to the scenario picker")


## An encounter is left for exploration, and only a devitalised duo leaves the dungeon.
func _check_leaving_the_dungeon(ctx: Dictionary) -> void:
	print("[leaving the dungeon]")
	var scene = ctx.scene
	get_tree().current_scene = scene
	# One character down, the other ran: still in the dungeon.
	GameSession.set_den(GameSession.PartySlot.MAIN, 0)
	GameSession.set_den(GameSession.PartySlot.TEAMMATE, 40)
	scene._on_encounter_finished(&"fled", [])
	for i in 5:
		await get_tree().process_frame
	_check(
		TransitionManager._fade.modulate.a == 0.0,
		"one character devitalised: the duo stays in the dungeon"
	)
	# Both down: out of the dungeon — which, in dev, is the scenario picker.
	GameSession.set_den(GameSession.PartySlot.TEAMMATE, 0)
	scene._on_encounter_finished(&"defeat", [])
	for i in 5:
		await get_tree().process_frame
	_check(
		TransitionManager._fade.modulate.a > 0.0, "the whole duo devitalised: it leaves the dungeon"
	)


## Distances are walked, not measured as the crow flies: a pillar stands at (2, 0, 3).
func _check_walking_distances(ctx: Dictionary) -> void:
	print("[walking distances]")
	var steps: Dictionary = ctx.dm.walking_distances(Vector3i(2, 0, 2), 6)
	_check(not steps.has(Vector3i(2, 0, 3)), "a pillar is not reachable")
	_check(
		steps.get(Vector3i(2, 0, 4), -1) == 4,
		"going around it takes 4 steps (%d)" % steps.get(Vector3i(2, 0, 4), -1)
	)


# --------------------------------------------------------------------------
# Into the encounter: every member arrives with its own state
# --------------------------------------------------------------------------


func _check_encounter_states() -> void:
	print("[into the encounter]")
	var ui = ENCOUNTER.instantiate()
	get_tree().root.add_child(ui)
	var states := [
		{"den": 20, "max_den": 60, "eth": 5, "max_eth": 40},
		{"den": 30, "max_den": 30, "eth": 20, "max_eth": 20},
	]
	ui.begin([&"draka", &"kalilk"], [&"ravbak", &"skorpis"], {}, states, 7)
	var rivals: Array = ui._manager.all_rivals
	_check(rivals.size() == 2, "both members are in the encounter")
	if rivals.size() == 2:
		var r0: EncounterIndividual = rivals[0]
		_check(
			r0.max_den == 60 and r0.den == 20 and r0.max_eth == 40 and r0.eth == 5,
			(
				"the first arrives with its DEN and ETH (%d/%d, %d/%d)"
				% [r0.den, r0.max_den, r0.eth, r0.max_eth]
			)
		)
	ui.queue_free()
	await get_tree().process_frame
