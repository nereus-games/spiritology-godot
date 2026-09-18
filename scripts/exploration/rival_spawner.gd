## Makes rival groups appear in a dungeon, following its [DungeonConfig].
##
## The rule, from level design:
## - the dungeon has S spawn points, tiles where a group may appear;
## - P groups appear on first entering it ([method populate]), then N more every T turns
##   ([method on_turn]);
## - each group is composed at random X % of the time — varieties from a list, a number of
##   individuals, a maximum DEN and ETH each, all drawn within bounds — and otherwise picked from
##   a list of special compositions ([method roll_composition]);
## - outside that system, fixed groups appear once, on their own tile, on first entry.
##
## A spawn point is only used when it is free, and not on or next to the player: a group that
## appears in contact would open an encounter nobody saw coming. A spawn with no usable point is
## skipped rather than forced somewhere else.
##
## No `class_name` (the CLI class-cache trap): preloaded.
extends RefCounted

const RivalMember := preload("res://scripts/exploration/rival_member.gd")
const RIVAL_SCENE := preload("res://scenes/exploration/rival/rival.tscn")

var config: DungeonConfig
var rng := RandomNumberGenerator.new()
var _dungeon


## A negative `seed` draws a random one; a fixed one makes every composition reproducible.
func _init(p_config: DungeonConfig, dungeon, seed: int = -1) -> void:
	config = p_config
	_dungeon = dungeon
	if seed < 0:
		rng.randomize()
	else:
		rng.seed = seed


## First entry: the fixed groups on their tiles, then [member DungeonConfig.initial_spawns]
## groups on spawn points. Returns the groups that appeared.
func populate() -> Array:
	var spawned: Array = []
	for group in config.fixed_groups:
		var members := _members_of(group)
		if members.is_empty():
			continue
		spawned.append(spawn_group(members, _dungeon.free_tile_near(group.tile)))
	spawned.append_array(spawn_groups(config.initial_spawns))
	return spawned


## Called on every exploration turn: every [member DungeonConfig.spawn_interval_turns] turns,
## [member DungeonConfig.spawns_per_wave] more groups. Returns the groups that appeared.
func on_turn(turn: int) -> Array:
	var interval := config.spawn_interval_turns
	if interval <= 0 or turn <= 0 or turn % interval != 0:
		return []
	return spawn_groups(config.spawns_per_wave)


## Up to `count` groups, each on a different free spawn point.
func spawn_groups(count: int) -> Array:
	var spawned: Array = []
	var points := free_spawn_points()
	for i in mini(count, points.size()):
		var members := roll_composition()
		if members.is_empty():
			break  # nothing to compose a group from
		var index := rng.randi_range(0, points.size() - 1)
		spawned.append(spawn_group(members, points[index]))
		points.remove_at(index)
	return spawned


## The spawn points a group may appear on right now: on the floor, unoccupied, and neither on
## the player's tile nor next to it.
func free_spawn_points() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var player: Vector3i = _dungeon.player_tile()
	for point in config.spawn_points:
		if not _dungeon.is_walkable(point):
			continue
		var d: Vector3i = (point - player).abs()
		if point.y == player.y and d.x + d.z <= 1:
			continue
		out.append(point)
	return out


## The members of one new group, as `rival_member.gd` instances: drawn at random with the
## chance [member DungeonConfig.random_composition_chance], a special composition otherwise.
## Falls back on whichever of the two the dungeon actually provides; empty when it provides
## neither.
func roll_composition() -> Array:
	var can_draw := not config.possible_species.is_empty() and config.group_size_max > 0
	var can_pick := not config.special_compositions.is_empty()
	var draw := can_draw and (not can_pick or rng.randf() < config.random_composition_chance)
	if draw:
		return _draw_members()
	if can_pick:
		var index := rng.randi_range(0, config.special_compositions.size() - 1)
		return _members_of(config.special_compositions[index])
	return []


func _draw_members() -> Array:
	var members: Array = []
	var size := rng.randi_range(config.group_size_min, config.group_size_max)
	for i in size:
		var species: StringName = config.possible_species[rng.randi_range(
			0, config.possible_species.size() - 1
		)]
		var max_den := rng.randi_range(config.member_max_den_min, config.member_max_den_max)
		var max_eth := rng.randi_range(config.member_max_eth_min, config.member_max_eth_max)
		members.append(RivalMember.new(species, max_den, max_eth))
	return members


func _members_of(group: RivalGroupData) -> Array:
	var members: Array = []
	if group == null:
		return members
	for m in group.members:
		if m != null:
			members.append(RivalMember.new(m.species_id, m.max_den, m.max_eth))
	return members


## Puts a group of `members` on `tile`. It registers itself with the dungeon once in the tree.
func spawn_group(members: Array, tile: Vector3i) -> Node:
	var group = RIVAL_SCENE.instantiate()
	group.members = members
	group.position = _dungeon.tile_to_world(tile)
	_dungeon.add_child(group)
	return group
