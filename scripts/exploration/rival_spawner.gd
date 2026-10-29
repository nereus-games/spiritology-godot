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
## A spawn point is never the player's tile nor next to it: a group that appears in contact would
## open an encounter nobody saw coming. Free points go first; when every one is occupied the new
## group appears anyway, and the occupant is pushed to an adjacent tile, by the same rule as a
## Teleport Gate's arrival ([method TileSearch.push_group_aside]). Nothing spawns past
## [member DungeonConfig.rival_limit] groups on the map.
##
## Varieties of a random group are weighted by their rarity in the dungeon: rare 1, normal and
## common by [BalanceData].
##
## ## TODO(forlorn): about 1 % of spawned rivals should be Forlorn, with the doc's table of
## bonuses. That needs the Forlorn individual (roadmap, section 4): a variant of a species on
## [RivalMember] and in the encounter. The roll belongs in [method spawn_group], once a member can
## carry the flag.
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
		spawned.append(spawn_group(members, _dungeon.tile_search.free_tile_near(group.tile)))
	spawned.append_array(spawn_groups(config.initial_spawns))
	return spawned


## Called on every exploration turn: every [member DungeonConfig.spawn_interval_turns] turns,
## [member DungeonConfig.spawns_per_wave] more groups. Returns the groups that appeared.
func on_turn(turn: int) -> Array:
	var interval := config.spawn_interval_turns
	if interval <= 0 or turn <= 0 or turn % interval != 0:
		return []
	return spawn_groups(wave_size())


## Groups in the next wave: [member DungeonConfig.spawns_per_wave], widened by
## [member BalanceData.wave_psy_extra_groups] above [member BalanceData.wave_psy_threshold] PSY.
## The doc has waves "grow wider first", and the interval shrink only if that is not enough.
func wave_size() -> int:
	var balance := BalanceData.current()
	if GameSession.psy_score > balance.wave_psy_threshold:
		return config.spawns_per_wave + balance.wave_psy_extra_groups
	return config.spawns_per_wave


## How many more groups the dungeon's spawn limit allows right now. Large when there is none.
func room_left() -> int:
	if config.rival_limit <= 0:
		return 1 << 30
	return maxi(0, config.rival_limit - _dungeon.rivals().size())


## Up to `count` groups, on spawn points and within the spawn limit. Free points are used first,
## each once; when none is left, a group takes an occupied point and pushes its occupant aside.
func spawn_groups(count: int) -> Array:
	var spawned: Array = []
	var free := free_spawn_points()
	var occupied := occupied_spawn_points()
	while spawned.size() < count and room_left() > 0:
		var members := roll_composition()
		if members.is_empty():
			break  # nothing to compose a group from
		var group = null
		if not free.is_empty():
			var index := rng.randi_range(0, free.size() - 1)
			group = spawn_group(members, free[index])
			free.remove_at(index)
		else:
			group = _spawn_pushing(members, occupied)
		if group == null:
			break  # no point left, free or pushable
		spawned.append(group)
	return spawned


## Up to `count` groups on free tiles within `radius` of `origin`, never on the player's tile, and
## within the spawn limit. Composed by the normal rules. For spawns that do not come from the
## dungeon's own points — examined decor.
func spawn_groups_near(origin: Vector3i, count: int, radius: int) -> Array:
	var spawned: Array = []
	var player: Vector3i = _dungeon.player_tile()
	var spots: Array[Vector3i] = []
	for tile in _dungeon.tile_search.free_tiles_near(origin, radius):
		if tile != player:
			spots.append(tile)
	for tile in spots:
		if spawned.size() >= count or room_left() <= 0:
			break
		var members := roll_composition()
		if members.is_empty():
			break
		spawned.append(spawn_group(members, tile))
	return spawned


## Spawns on a random occupied point, pushing its occupant aside. A point whose occupant cannot
## be moved is dropped from `occupied` and another is tried. Null when none works.
func _spawn_pushing(members: Array, occupied: Array[Vector3i]) -> Node:
	while not occupied.is_empty():
		var index := rng.randi_range(0, occupied.size() - 1)
		var point := occupied[index]
		var there: Node = _dungeon.occupant_at(point)
		if there == null or _dungeon.tile_search.push_group_aside(there):
			return spawn_group(members, point)
		occupied.remove_at(index)
	return null


## The spawn points a group may appear on right now: on the floor, unoccupied, outside any safe
## area, and neither on the player's tile nor next to it.
func free_spawn_points() -> Array[Vector3i]:
	return _spawn_points(false)


## The same, but occupied by a rival group: where a new group may still appear, pushing it aside.
func occupied_spawn_points() -> Array[Vector3i]:
	return _spawn_points(true)


func _spawn_points(occupied: bool) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var player: Vector3i = _dungeon.player_tile()
	for point in config.spawn_points:
		if not _dungeon.is_floor(point) or _dungeon.safe_areas.has(point):
			continue
		if _dungeon.is_blocked_by_mechanism(point):
			continue
		if (_dungeon.occupant_at(point) != null) != occupied:
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


## The weight of a variety in a random draw: its rarity here, rare 1, normal and common from
## [BalanceData].
func species_weight(species: StringName) -> int:
	var balance := BalanceData.current()
	if config.rare_species.has(species):
		return 1
	if config.common_species.has(species):
		return maxi(1, balance.spawn_weight_common)
	return maxi(1, balance.spawn_weight_normal)


func _draw_species() -> StringName:
	var total := 0
	for species in config.possible_species:
		total += species_weight(species)
	var roll := rng.randi_range(1, total)
	for species in config.possible_species:
		roll -= species_weight(species)
		if roll <= 0:
			return species
	return config.possible_species[0]


func _draw_members() -> Array:
	var members: Array = []
	var size := rng.randi_range(config.group_size_min, config.group_size_max)
	for i in size:
		var species := _draw_species()
		var max_den := rng.randi_range(config.member_max_den_min, config.member_max_den_max)
		var max_eth := rng.randi_range(config.member_max_eth_min, config.member_max_eth_max)
		var member := RivalMember.new(species, max_den, max_eth)
		member.objects = roll_objects(species)
		members.append(member)
	return members


func _members_of(group: RivalGroupData) -> Array:
	var members: Array = []
	if group == null:
		return members
	for m in group.members:
		if m != null:
			var member := RivalMember.new(m.species_id, m.max_den, m.max_eth)
			member.objects = roll_objects(m.species_id)
			members.append(member)
	return members


## The objects a new rival of this variety carries: each one the variety may drop (`loot` in its
## data) with the chance [member BalanceData.rival_object_chance]. Rolled once, here, so what a
## rival carries is fixed from its first appearance and an Examine only reveals it.
func roll_objects(species: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	var path := "res://data/species/%s.tres" % species
	if not ResourceLoader.exists(path):
		return out
	var data: SpeciesData = load(path)
	var chance := BalanceData.current().rival_object_chance
	for id in data.loot:
		if rng.randf() < chance:
			out.append(id)
	return out


## Puts a group of `members` on `tile`. It registers itself with the dungeon once in the tree.
func spawn_group(members: Array, tile: Vector3i) -> Node:
	var group = RIVAL_SCENE.instantiate()
	group.members = members
	group.position = _dungeon.tile_to_world(tile)
	_dungeon.add_child(group)
	return group
