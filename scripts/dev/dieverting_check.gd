## Headless check on the dieverting against the design doc ("Mechanisms"). Exercises the
## destroy/submit choice and all 6 outcomes of the die, one at a time with the outcome forced, in
## the real "chests" scenario — so with a real entrance, exit, player and dungeon.
##
## Run with: Godot --headless --path . res://scenes/dev/dieverting_check.tscn
## As a start scene rather than --script; see geometry_check.gd.
extends Node

const ScenarioCatalog := preload("res://scripts/dev/scenario_catalog.gd")
const EXPLORATION := preload("res://scenes/exploration/exploration.tscn")
const Dieverting := preload("res://scripts/exploration/mechanisms/dieverting.gd")
const DungeonMechanism := preload("res://scripts/exploration/mechanisms/dungeon_mechanism.gd")

## Cell of the first die in the "chests" scenario.
const DIE_CELL := Vector3i(1, 0, 5)

var _fails: Array[String] = []
## The latest messages the dungeon posted, which the HUD shows in its feedback banner.
var _messages: Array[String] = []


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
	await _check_choice()
	await _check_auto_submit()
	await _check_roll_animation()
	for outcome in Dieverting.Outcome.values():
		await _check_outcome(outcome)
	print("")
	if _fails.is_empty():
		print("ALL OK")
	else:
		print("FAILURES: %s" % [_fails])
	get_tree().quit(0 if _fails.is_empty() else 1)


# --------------------------------------------------------------------------
# The test field
# --------------------------------------------------------------------------


## Builds the "chests" scenario, puts the player on the die's cell, and returns
## {scene, dm, player, die}.
func _setup() -> Dictionary:
	ScenarioCatalog.selected_id = &"chests"
	var scene = EXPLORATION.instantiate()
	get_tree().root.add_child(scene)
	await get_tree().process_frame
	var dm = scene.get_node("DungeonManager")
	var player = scene.get_node("Player")
	_messages.clear()
	dm.message_posted.connect(func(text: String) -> void: _messages.append(text))
	var die = null
	for m in dm.mechanisms_at(DIE_CELL):
		if m.has_method("submit"):
			die = m
	if die != null:
		die.roll_duration = 0.0  # tumble short-circuited, so the logic tests stay instant
	player.teleport_to(DIE_CELL)
	return {"scene": scene, "dm": dm, "player": player, "die": die}


func _teardown(ctx: Dictionary) -> void:
	ctx.scene.queue_free()
	await get_tree().process_frame


func _inventory_total() -> int:
	var total := 0
	for count in GameSession.inventory.values():
		total += count
	return total


## The chest on the die's cell, or null: a mechanism with fixed contents.
func _chest_at_die(dm) -> Node:
	for m in dm.mechanisms_at(DIE_CELL):
		if "fixed_loot" in m and not m.fixed_loot.is_empty():
			return m
	return null


# --------------------------------------------------------------------------
# The destroy/submit choice, offered when the player holds a spade or a rune stone
# --------------------------------------------------------------------------


func _check_choice() -> void:
	print("[destroy/submit choice]")
	var ctx := await _setup()
	var die = ctx.die
	_check(die != null, "a dieverting on %s" % DIE_CELL)
	GameSession.inventory.clear()
	GameSession.add_object(&"spade", 1)
	die.on_enter(ctx.player)
	_check(
		die.is_active() and die.is_pending(),
		"with a spade: the die waits for the choice, and does not roll"
	)
	var actions: Array = ctx.dm.actions_for(DIE_CELL, Vector3i(0, 0, 1), ctx.player)
	var ids := []
	for a in actions:
		ids.append(a.id)
	_check(
		&"destroy_dieverting" in ids and &"submit_dieverting" in ids,
		"both actions are offered (%s)" % [ids]
	)
	_check(die.destroy(ctx.player), "destroying consumes a destroyer object")
	_check(not GameSession.has_object(&"spade"), "the spade is spent")
	_check(not die.is_active() and not die.is_pending(), "the destroyed die is inert")
	_check(_messages.size() == 1, 'the destruction is announced: "%s"' % ["".join(_messages)])
	_check(
		ctx.dm.actions_for(DIE_CELL, Vector3i(0, 0, 1), ctx.player).is_empty(),
		"no action left on the cell"
	)
	await _teardown(ctx)


func _check_auto_submit() -> void:
	print("[no destroyer object: the die goes off by itself]")
	var ctx := await _setup()
	GameSession.inventory.clear()
	ctx.die.on_enter(ctx.player)
	_check(not ctx.die.is_active(), "the die rolled on its own")
	_check(not ctx.die.is_pending(), "no choice left pending")
	await _teardown(ctx)


## The tumble for real, at its nominal duration: the die leaves its resting cell, locks the
## controls for the throw, stops on the rolled face and presents it to the player.
func _check_roll_animation() -> void:
	print("[the die's tumble]")
	var ctx := await _setup()
	var die = ctx.die
	var player = ctx.player
	GameSession.inventory.clear()
	die.roll_duration = 0.25
	die.roll_hold = 0.1
	var marker: MeshInstance3D = die._marker
	_check(marker != null, "the die has a visual")
	var pips := marker.get_child_count() if marker != null else 0
	_check(pips == 21, "%d pips across the 6 faces (1+2+3+4+5+6)" % pips)
	var rest: Vector3 = marker.position
	var face := Dieverting.Outcome.ADD_OBJECTS + 1  # a harmless outcome: nothing moves around
	die.submit(player, Dieverting.Outcome.ADD_OBJECTS)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(player.input_locked, "the controls are locked during the throw")
	_check(marker.position != rest, "the die leaves the floor to tumble into view")
	await get_tree().create_timer(1.2).timeout
	_check(not player.input_locked, "the controls come back once it lands")
	_check(marker.position.is_equal_approx(rest), "the die has come down onto its cell")
	# The rolled face is the one looking at the player. The player faces +z, so the face points
	# towards -z once the die has landed.
	var toward_player: Vector3 = -Vector3(player.facing_delta().x, 0.0, player.facing_delta().z)
	var normal: Vector3 = marker.basis * Dieverting.FACE_NORMALS[face]
	_check(
		normal.normalized().dot(toward_player.normalized()) > 0.95,
		(
			"face %d is turned towards the player (dot product %.2f)"
			% [face, normal.normalized().dot(toward_player.normalized())]
		)
	)
	await _teardown(ctx)


# --------------------------------------------------------------------------
# The 6 outcomes
# --------------------------------------------------------------------------


func _check_outcome(outcome: int) -> void:
	var ctx := await _setup()
	var dm = ctx.dm
	var player = ctx.player
	var die = ctx.die
	GameSession.inventory.clear()
	GameSession.add_object(&"tea_drop", 2)
	GameSession.add_object(&"smoke_bomb", 2)
	var before_objects := _inventory_total()
	var before_eth: int = GameSession.get_eth(GameSession.PartySlot.MAIN)
	var before_den: int = GameSession.get_den(GameSession.PartySlot.MAIN)
	var before_rivals: int = dm.rivals().size()

	match outcome:
		Dieverting.Outcome.TELEPORT_ENTRANCE_LOSE_OBJECTS:
			print("[1. back to the entrance + objects lost]")
			await die.submit(player, outcome)
			_check(
				player.cell == dm.entrance_cell(),
				"the player is at the entrance %s (%s)" % [dm.entrance_cell(), player.cell]
			)
			_check(
				_inventory_total() == before_objects - die.objects_lost,
				"%d objects lost" % die.objects_lost
			)
			var chest := _chest_at_die(dm)
			_check(chest != null, "a chest is placed where the die was")
			if chest != null:
				_check(
					chest.fixed_loot.size() == die.objects_lost,
					"the chest holds exactly the objects lost (%s)" % [chest.fixed_loot]
				)
				chest.on_enter(player)
				_check(_inventory_total() == before_objects, "reopening it restores the count")
		Dieverting.Outcome.TELEPORT_ENTRANCE_LOSE_ETH:
			print("[2. back to the entrance + ETH lost]")
			await die.submit(player, outcome)
			_check(
				player.cell == dm.entrance_cell(),
				"the player is at the entrance (%s)" % player.cell
			)
			_check(
				(
					(
						GameSession.get_eth(GameSession.PartySlot.MAIN)
						== before_eth - die.eth_lost_each
					)
					and (
						GameSession.get_eth(GameSession.PartySlot.TEAMMATE)
						== before_eth - die.eth_lost_each
					)
				),
				"BOTH characters lose %d ETH" % die.eth_lost_each
			)
			_check(_inventory_total() == before_objects, "no object lost")
		Dieverting.Outcome.SPAWN_RIVALS:
			print("[3. rival groups appear]")
			await die.submit(player, outcome)
			await get_tree().process_frame  # the rivals' _ready registers them with the dungeon
			var spawned: int = dm.rivals().size() - before_rivals
			_check(
				spawned >= 1 and spawned <= die.rival_spawn_max,
				"%d group(s) spawned (1 to %d)" % [spawned, die.rival_spawn_max]
			)
			var far := true
			for rival in dm.rivals():
				var d: Vector3i = rival.cell - player.cell
				if absi(d.x) + absi(d.z) > die.rival_spawn_radius or rival.cell == player.cell:
					far = false
			_check(far, "all of them appear nearby (%d cells or less)" % die.rival_spawn_radius)
			_check(player.cell == DIE_CELL, "the player is not moved")
		Dieverting.Outcome.TELEPORT_EXIT_LOSE_OBJECTS_DEN:
			print("[4. sent to an exit + objects lost + DEN lost]")
			await die.submit(player, outcome)
			_check(
				player.cell in dm.exit_cells(),
				"the player is on an exit %s (%s)" % [dm.exit_cells(), player.cell]
			)
			_check(
				_inventory_total() == before_objects - die.objects_lost,
				"%d objects lost" % die.objects_lost
			)
			_check(_chest_at_die(dm) != null, "a chest is placed where the die was")
			_check(
				(
					(
						GameSession.get_den(GameSession.PartySlot.MAIN)
						== before_den - die.den_lost_each
					)
					and (
						GameSession.get_den(GameSession.PartySlot.TEAMMATE)
						== before_den - die.den_lost_each
					)
				),
				"BOTH characters lose %d DEN" % die.den_lost_each
			)
		Dieverting.Outcome.DESTROY_OBJECTS:
			print("[5. objects destroyed]")
			await die.submit(player, outcome)
			var lost := before_objects - _inventory_total()
			_check(
				lost >= 1 and lost <= die.max_objects_delta,
				"%d object(s) destroyed (up to %d)" % [lost, die.max_objects_delta]
			)
			_check(_chest_at_die(dm) == null, "destroyed, so NO chest, unlike outcomes 1 and 4")
			_check(player.cell == DIE_CELL, "the player is not moved")
		Dieverting.Outcome.ADD_OBJECTS:
			print("[6. objects gained]")
			await die.submit(player, outcome)
			var gained := _inventory_total() - before_objects
			_check(
				gained >= 1 and gained <= die.max_objects_delta,
				"%d object(s) gained (up to %d)" % [gained, die.max_objects_delta]
			)
			_check(player.cell == DIE_CELL, "the player is not moved")

	_check(not die.is_active(), "the die is consumed once it has rolled")
	_check(
		die._marker.material_override.albedo_color.is_equal_approx(DungeonMechanism.SPENT_COLOR),
		"a rolled die is greyed out: no longer actionable, so no longer looking active"
	)
	_check(
		is_equal_approx(die._marker.scale.y, 1.0),
		"...but keeps its shape, so the rolled face stays readable"
	)
	# The FIRST message announces the throw. Outcome 1 adds a second one: the test reopens the
	# chest it dropped, which announces its loot (see chest.gd).
	_check(
		not _messages.is_empty() and _messages[0].contains(str(outcome + 1)),
		(
			'the result is announced to the player: "%s"'
			% [_messages[0] if not _messages.is_empty() else ""]
		)
	)
	await _teardown(ctx)
