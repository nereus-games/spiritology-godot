## Headless check on the rest of the design doc's "Rival Spawning" rules, next to
## rival_spawn_check.gd (which holds P, N, T and X): species weighted by the dungeon's rarity, the
## spawn limit, an occupied spawn point (the occupant is pushed aside), wider waves at a high PSY,
## and examined decor spawning rivals at a high PSY.
##
## Runs on the "rivals" scenario. Run with:
## Godot --headless --path . res://scenes/dev/spawn_rules_check.tscn
## As a start scene rather than --script; see geometry_check.gd.
extends Node

const ScenarioCatalog := preload("res://scripts/dev/scenario_catalog.gd")
const EXPLORATION := preload("res://scenes/exploration/exploration.tscn")
const RivalSpawner := preload("res://scripts/exploration/rival_spawner.gd")
const ExaminableDecor := preload("res://scripts/exploration/mechanisms/examinable_decor.gd")

const SEED := 20261021

## Draws to measure the rarity split. The shares are 50 / 33 / 17 %; the standard deviation over
## this many is under one point, so only a real regression crosses the five allowed below.
const DRAWS := 3000
const SHARE_TOLERANCE := 0.05

## Examinations to measure the 45 % chance: the standard deviation is 3.5 points, the tolerance
## 12.
const EXAMS := 200
const EXAM_TOLERANCE := 0.12

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
	ScenarioCatalog.selected_id = &"rivals"
	var scene = EXPLORATION.instantiate()
	get_tree().root.add_child(scene)
	await get_tree().process_frame
	var ctx := {
		"scene": scene, "dm": scene.get_node("DungeonManager"), "player": scene.get_node("Player")
	}
	ctx.player.teleport_to(Vector3i(4, 0, 0))
	_check_rarity(ctx)
	await _check_limit(ctx)
	await _check_occupied_points(ctx)
	await _check_waves(ctx)
	await _check_decor(ctx)
	scene.queue_free()
	await get_tree().process_frame
	print("")
	if _fails.is_empty():
		print("ALL OK")
	else:
		print("FAILURES: %s" % [_fails])
	get_tree().quit(0 if _fails.is_empty() else 1)


func _clear_rivals(dm) -> void:
	for r in dm.rivals():
		r.remove_from_dungeon()
	await get_tree().process_frame


## A copy of the dungeon's rules, to bend without touching the shared resource.
func _config_of(dm) -> DungeonConfig:
	return dm.config.duplicate()


# --------------------------------------------------------------------------
# Rarity: common, normal and rare varieties are drawn 3 : 2 : 1
# --------------------------------------------------------------------------


func _check_rarity(ctx: Dictionary) -> void:
	print("[rarity]")
	var config := _config_of(ctx.dm)
	config.possible_species = [&"ravbak", &"kalilk", &"skorpis"]
	config.common_species = [&"ravbak"]
	config.rare_species = [&"skorpis"]
	config.random_composition_chance = 1.0
	config.group_size_min = 1
	config.group_size_max = 1
	var spawner = RivalSpawner.new(config, ctx.dm, SEED)
	var counts := {&"ravbak": 0, &"kalilk": 0, &"skorpis": 0}
	for i in DRAWS:
		counts[spawner.roll_composition()[0].species_id] += 1
	var balance := BalanceData.current()
	var total: float = balance.spawn_weight_common + balance.spawn_weight_normal + 1
	var expected := {
		&"ravbak": balance.spawn_weight_common / total,
		&"kalilk": balance.spawn_weight_normal / total,
		&"skorpis": 1.0 / total,
	}
	for species in counts:
		var share: float = float(counts[species]) / DRAWS
		_check(
			absf(share - expected[species]) <= SHARE_TOLERANCE,
			(
				"%s comes up %.0f %% of the time (expected %.0f %%)"
				% [species, share * 100.0, expected[species] * 100.0]
			)
		)
	_check(
		counts[&"ravbak"] > counts[&"kalilk"] and counts[&"kalilk"] > counts[&"skorpis"],
		"common > normal > rare"
	)


# --------------------------------------------------------------------------
# The spawn limit
# --------------------------------------------------------------------------


func _check_limit(ctx: Dictionary) -> void:
	print("[spawn limit]")
	var dm = ctx.dm
	await _clear_rivals(dm)
	var config := _config_of(dm)
	config.rival_limit = 3
	var spawner = RivalSpawner.new(config, dm, SEED)
	var first := spawner.spawn_groups(10)
	await get_tree().process_frame
	_check(
		first.size() == 3 and dm.rivals().size() == 3,
		"10 asked, the limit of 3 holds (%d)" % dm.rivals().size()
	)
	_check(spawner.spawn_groups(1).is_empty(), "at the limit nothing more appears")
	dm.rivals()[0].remove_from_dungeon()
	await get_tree().process_frame
	_check(spawner.spawn_groups(5).size() == 1, "one group gone, one more fits")
	await get_tree().process_frame
	var none := _config_of(dm)
	none.rival_limit = 0
	var free_spawner = RivalSpawner.new(none, dm, SEED)
	_check(free_spawner.room_left() > 100, "no limit configured: no cap")
	await _clear_rivals(dm)


# --------------------------------------------------------------------------
# Occupied spawn points: the group appears anyway, the occupant is pushed
# --------------------------------------------------------------------------


func _check_occupied_points(ctx: Dictionary) -> void:
	print("[occupied spawn points]")
	var dm = ctx.dm
	var player = ctx.player
	await _clear_rivals(dm)
	var config := _config_of(dm)
	var spawner = RivalSpawner.new(config, dm, SEED)
	player.teleport_to(Vector3i(4, 0, 0))
	spawner.spawn_groups(config.spawn_points.size())
	await get_tree().process_frame
	var before := {}
	for g in dm.rivals():
		before[g] = g.tile
	_check(
		before.size() == config.spawn_points.size() and spawner.free_spawn_points().is_empty(),
		"every spawn point is taken"
	)
	var spawned := spawner.spawn_groups(1)
	await get_tree().process_frame
	_check(
		spawned.size() == 1 and dm.rivals().size() == before.size() + 1,
		"a new group appears anyway"
	)
	var moved: Array = []
	for g in before:
		if g.tile != before[g]:
			moved.append(g)
	_check(moved.size() == 1, "exactly one occupant was moved (%d)" % moved.size())
	if moved.size() == 1 and spawned.size() == 1:
		var d: Vector3i = (moved[0].tile - before[moved[0]]).abs()
		_check(d.x + d.z == 1 and d.y == 0, "pushed to an adjacent tile")
		_check(spawned[0].tile == before[moved[0]], "the newcomer took the vacated spawn point")
	var tiles := {}
	for g in dm.rivals():
		tiles[g.tile] = true
	_check(tiles.size() == dm.rivals().size(), "no two groups share a tile")

	# Never the player's point, nor those next to them, however occupied the rest.
	var watched: Vector3i = config.spawn_points[0]
	player.teleport_to(watched + Vector3i(0, 0, 1))
	var clean := true
	for i in 12:
		for g in spawner.spawn_groups(1):
			var gap: Vector3i = (g.tile - player.tile).abs()
			if gap.x + gap.z <= 1:
				clean = false
		await get_tree().process_frame
	_check(clean, "never on or next to the player, even with every point taken")
	await _clear_rivals(dm)


# --------------------------------------------------------------------------
# Waves widen at a high PSY
# --------------------------------------------------------------------------


func _check_waves(ctx: Dictionary) -> void:
	print("[waves at high PSY]")
	var dm = ctx.dm
	var scene = ctx.scene
	var config: DungeonConfig = dm.config
	var balance := BalanceData.current()
	var saved_psy: int = GameSession.psy_score
	await _clear_rivals(dm)
	GameSession.psy_score = balance.wave_psy_threshold
	scene._on_turn_advanced(config.spawn_interval_turns)
	_check(
		dm.rivals().size() == config.spawns_per_wave,
		"at the threshold the wave keeps its size (%d)" % dm.rivals().size()
	)
	await _clear_rivals(dm)
	GameSession.psy_score = balance.wave_psy_threshold + 1
	scene._on_turn_advanced(config.spawn_interval_turns)
	_check(
		dm.rivals().size() == config.spawns_per_wave + balance.wave_psy_extra_groups,
		"above it the wave is wider (%d)" % dm.rivals().size()
	)
	GameSession.psy_score = saved_psy
	await _clear_rivals(dm)


# --------------------------------------------------------------------------
# Examined decor
# --------------------------------------------------------------------------


## Examines a fresh piece of decor and returns the groups on the map afterwards.
func _examine_new_decor(ctx: Dictionary) -> Array:
	var decor = ScenarioCatalog._place(ctx.dm, ExaminableDecor, Vector3i(4, 0, 4))
	await get_tree().process_frame
	decor.examine(ctx.player)
	await get_tree().process_frame
	var groups: Array = ctx.dm.rivals()
	decor.queue_free()
	return groups


func _check_decor(ctx: Dictionary) -> void:
	print("[examined decor]")
	var dm = ctx.dm
	var balance := BalanceData.current()
	var saved_psy: int = GameSession.psy_score
	var saved_chance := balance.decor_spawn_chance
	var saved_max := balance.decor_spawn_groups_max
	await _clear_rivals(dm)
	ctx.player.teleport_to(Vector3i(4, 0, 5))

	balance.decor_spawn_chance = 1.0
	GameSession.psy_score = balance.decor_psy_threshold
	_check((await _examine_new_decor(ctx)).is_empty(), "at the PSY threshold nothing appears")
	GameSession.psy_score = balance.decor_psy_threshold + 1
	var groups := await _examine_new_decor(ctx)
	_check(not groups.is_empty(), "above it, a sure chance brings rivals (%d)" % groups.size())
	var near := true
	for g in groups:
		var d: Vector3i = (g.tile - ctx.player.tile).abs()
		if g.tile == ctx.player.tile or d.x + d.z > balance.decor_spawn_radius:
			near = false
	_check(
		groups.size() <= balance.decor_spawn_groups_max and near,
		"no more than the maximum, close by, never on the player's tile"
	)
	await _clear_rivals(dm)

	balance.decor_spawn_chance = 0.0
	_check((await _examine_new_decor(ctx)).is_empty(), "a null chance brings nothing")

	# The spawn limit holds for decor too.
	balance.decor_spawn_chance = 1.0
	var saved: DungeonConfig = dm.config
	var capped := _config_of(dm)
	capped.rival_limit = 1
	dm.config = capped
	RivalSpawner.new(capped, dm, SEED).spawn_groups(1)
	await get_tree().process_frame
	_check((await _examine_new_decor(ctx)).size() == 1, "at the spawn limit decor brings nothing")
	dm.config = saved
	await _clear_rivals(dm)

	# The 45 % chance.
	balance.decor_spawn_chance = 0.45
	balance.decor_spawn_groups_max = 1
	var hits := 0
	for i in EXAMS:
		if not (await _examine_new_decor(ctx)).is_empty():
			hits += 1
		await _clear_rivals(dm)
	var rate := float(hits) / EXAMS
	_check(
		absf(rate - 0.45) <= EXAM_TOLERANCE,
		"%.0f %% of examinations bring rivals (45 %%)" % [rate * 100.0]
	)

	balance.decor_spawn_chance = saved_chance
	balance.decor_spawn_groups_max = saved_max
	GameSession.psy_score = saved_psy
