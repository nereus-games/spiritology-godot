## Headless check on rival SPAWNS against the level-design rule: S spawn points, P groups on first
## entry, N more every T turns, a composition drawn at random X % of the time and picked from the
## special compositions otherwise, and fixed groups on their own tiles.
##
## Runs on the "rivals" scenario and its `data/dungeons/dev_rivals.tres`.
##
## Run with: Godot --headless --path . res://scenes/dev/rival_spawn_check.tscn
## As a start scene rather than --script; see geometry_check.gd.
extends Node

const ScenarioCatalog := preload("res://scripts/dev/scenario_catalog.gd")
const EXPLORATION := preload("res://scenes/exploration/exploration.tscn")
const RivalSpawner := preload("res://scripts/exploration/rival_spawner.gd")
const Dieverting := preload("res://scripts/exploration/mechanisms/dieverting.gd")

const SEED := 20260917

## Compositions rolled to measure the split between random and special ones. At X = 70 % the
## standard deviation over this many is 1.4 points, so the ±6 points allowed below is over four
## of them: a real regression fails, chance does not.
const ROLLS := 1000
const SPLIT_TOLERANCE := 0.06

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
	_check_first_entry(ctx)
	_check_compositions(ctx)
	_check_fallbacks(ctx)
	await _check_waves(ctx)
	await _check_spawn_points(ctx)
	await _check_dieverting(ctx)
	scene.queue_free()
	await get_tree().process_frame
	print("")
	if _fails.is_empty():
		print("ALL OK")
	else:
		print("FAILURES: %s" % [_fails])
	get_tree().quit(0 if _fails.is_empty() else 1)


## A group's members as comparable text: "ravbak 40/30, ravbak 40/30".
func _signature(members: Array) -> String:
	var parts: Array = []
	for m in members:
		parts.append("%s %d/%d" % [m.species_id, m.max_den, m.max_eth])
	return ", ".join(parts)


func _group_signature(group: RivalGroupData) -> String:
	var parts: Array = []
	for m in group.members:
		parts.append("%s %d/%d" % [m.species_id, m.max_den, m.max_eth])
	return ", ".join(parts)


func _clear_rivals(dm) -> void:
	for r in dm.rivals():
		r.remove_from_dungeon()
	await get_tree().process_frame


# --------------------------------------------------------------------------
# First entry: the fixed groups, and P groups on spawn points
# --------------------------------------------------------------------------


func _check_first_entry(ctx: Dictionary) -> void:
	print("[first entry]")
	var dm = ctx.dm
	var config: DungeonConfig = dm.config
	_check(
		config != null and config.id == &"dev_rivals", "the scenario runs under its dungeon rules"
	)
	if config == null:
		return
	var groups: Array = dm.rivals()
	_check(
		groups.size() == config.fixed_groups.size() + config.initial_spawns,
		(
			"%d groups: %d fixed + %d spawned"
			% [groups.size(), config.fixed_groups.size(), config.initial_spawns]
		)
	)
	var fixed: RivalGroupData = config.fixed_groups[0]
	var on_fixed_tile: Array = groups.filter(func(g): return g.tile == fixed.tile)
	_check(
		(
			on_fixed_tile.size() == 1
			and _signature(on_fixed_tile[0].members) == _group_signature(fixed)
		),
		"the fixed group stands on its tile %s, as written" % fixed.tile
	)
	var off_points: Array = []
	for g in groups:
		if g.tile != fixed.tile and not config.spawn_points.has(g.tile):
			off_points.append(g.tile)
	_check(off_points.is_empty(), "the others stand on spawn points %s" % [off_points])


# --------------------------------------------------------------------------
# Compositions: random within bounds X % of the time, special otherwise
# --------------------------------------------------------------------------


func _check_compositions(ctx: Dictionary) -> void:
	print("[compositions]")
	var config: DungeonConfig = ctx.dm.config
	var spawner = RivalSpawner.new(config, ctx.dm, SEED)
	var specials := {}
	for group in config.special_compositions:
		specials[_group_signature(group)] = true
	var random := 0
	var special_seen := {}
	var out_of_bounds: Array = []
	for i in ROLLS:
		var members: Array = spawner.roll_composition()
		var signature := _signature(members)
		if specials.has(signature):
			special_seen[signature] = true
			continue
		random += 1
		var problem := _bounds_problem(config, members)
		if problem != "" and out_of_bounds.size() < 5:
			out_of_bounds.append(problem)
	var share := float(random) / ROLLS
	_check(
		absf(share - config.random_composition_chance) <= SPLIT_TOLERANCE,
		(
			"%.0f %% of the groups drawn at random (X = %.0f %%)"
			% [share * 100.0, config.random_composition_chance * 100.0]
		)
	)
	_check(
		special_seen.size() == config.special_compositions.size(),
		"every special composition comes up (%d of %d)" % [special_seen.size(), specials.size()]
	)
	_check(
		out_of_bounds.is_empty(),
		(
			"random groups stay within the dungeon's bounds%s"
			% ("" if out_of_bounds.is_empty() else " — " + "; ".join(out_of_bounds))
		)
	)

	var a = RivalSpawner.new(config, ctx.dm, SEED)
	var b = RivalSpawner.new(config, ctx.dm, SEED)
	var same := true
	for i in 50:
		if _signature(a.roll_composition()) != _signature(b.roll_composition()):
			same = false
	_check(same, "the same seed rolls the same groups")


func _bounds_problem(config: DungeonConfig, members: Array) -> String:
	if members.size() < config.group_size_min or members.size() > config.group_size_max:
		return "%d members" % members.size()
	for m in members:
		if not config.possible_species.has(m.species_id):
			return "variety %s" % m.species_id
		if m.max_den < config.member_max_den_min or m.max_den > config.member_max_den_max:
			return "max DEN %d" % m.max_den
		if m.max_eth < config.member_max_eth_min or m.max_eth > config.member_max_eth_max:
			return "max ETH %d" % m.max_eth
		if m.den != m.max_den or m.eth != m.max_eth:
			return "a member that does not start full"
	return ""


## A dungeon that provides only one of the two sources uses that one, whatever X says.
func _check_fallbacks(ctx: Dictionary) -> void:
	print("[fallbacks]")
	var special := RivalGroupData.new()
	var member := RivalMemberData.new()
	member.species_id = &"skorpis"
	member.max_den = 70
	special.members = [member]

	var only_random := DungeonConfig.new()
	only_random.possible_species = [&"kalilk"]
	only_random.random_composition_chance = 0.5
	var only_special := DungeonConfig.new()
	only_special.special_compositions = [special]
	var neither := DungeonConfig.new()

	var r = RivalSpawner.new(only_random, ctx.dm, SEED)
	var s = RivalSpawner.new(only_special, ctx.dm, SEED)
	var all_random := true
	var all_special := true
	for i in 30:
		if _signature(r.roll_composition()) != "kalilk 50/50":
			all_random = false
		if _signature(s.roll_composition()) != "skorpis 70/50":
			all_special = false
	_check(all_random, "no special composition listed: every group is drawn at random")
	_check(all_special, "no variety listed: every group is a special composition")
	var n = RivalSpawner.new(neither, ctx.dm, SEED)
	_check(
		n.roll_composition().is_empty() and n.spawn_groups(3).is_empty(),
		"nothing to compose from: nothing spawns"
	)


# --------------------------------------------------------------------------
# Waves: N more groups every T turns
# --------------------------------------------------------------------------


func _check_waves(ctx: Dictionary) -> void:
	print("[waves]")
	var dm = ctx.dm
	var scene = ctx.scene
	var config: DungeonConfig = dm.config
	var interval := config.spawn_interval_turns
	await _clear_rivals(dm)
	var early := 0
	for turn in range(1, interval):
		scene._on_turn_advanced(turn)
		early += dm.rivals().size()
	_check(early == 0, "nothing appears before turn %d" % interval)
	scene._on_turn_advanced(interval)
	_check(
		dm.rivals().size() == config.spawns_per_wave,
		"turn %d: %d new group(s)" % [interval, dm.rivals().size()]
	)
	scene._on_turn_advanced(interval * 2)
	_check(
		dm.rivals().size() == config.spawns_per_wave * 2,
		"turn %d: %d more" % [interval * 2, config.spawns_per_wave]
	)
	await _clear_rivals(dm)


# --------------------------------------------------------------------------
# Spawn points: free ones only, never on or next to the player
# --------------------------------------------------------------------------


func _check_spawn_points(ctx: Dictionary) -> void:
	print("[spawn points]")
	var dm = ctx.dm
	var player = ctx.player
	var config: DungeonConfig = dm.config
	var spawner = RivalSpawner.new(config, dm, SEED)
	var watched: Vector3i = config.spawn_points[0]
	player.teleport_to(watched)
	var points: Array = spawner.free_spawn_points()
	_check(not points.has(watched), "no group appears on the player's tile")
	player.teleport_to(watched + Vector3i(0, 0, 1))
	_check(not spawner.free_spawn_points().has(watched), "nor next to the player")

	player.teleport_to(Vector3i(4, 0, 0))
	var spawned: Array = spawner.spawn_groups(config.spawn_points.size() + 5)
	await get_tree().process_frame
	var tiles := {}
	for g in spawned:
		tiles[g.tile] = true
	_check(
		spawned.size() == config.spawn_points.size() and tiles.size() == spawned.size(),
		"asked for more groups than points: one per point (%d)" % spawned.size()
	)
	_check(spawner.spawn_groups(1).is_empty(), "every point taken: nothing more appears")
	await _clear_rivals(dm)


# --------------------------------------------------------------------------
# The dieverting's SPAWN_RIVALS outcome follows the dungeon's composition rules
# --------------------------------------------------------------------------


func _check_dieverting(ctx: Dictionary) -> void:
	print("[dieverting]")
	var dm = ctx.dm
	var player = ctx.player
	var saved: DungeonConfig = dm.config
	var pairs := DungeonConfig.new()
	pairs.possible_species = [&"fliritus"]
	pairs.group_size_min = 2
	pairs.group_size_max = 2
	dm.config = pairs
	var die = ScenarioCatalog._place(dm, Dieverting, Vector3i(4, 0, 2))
	player.teleport_to(Vector3i(4, 0, 2))
	var ok := true
	for i in 5:
		die._spawn_rival_groups(player)
		await get_tree().process_frame
		for g in dm.rivals():
			if _signature(g.members) != "fliritus 50/50, fliritus 50/50":
				ok = false
		await _clear_rivals(dm)
	_check(ok, "the groups a die summons are composed by the dungeon's rules")
	dm.config = saved
	die.queue_free()
