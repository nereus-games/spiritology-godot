## What a dungeon can contain.
##
## Exists so the right heavy assets can be preloaded on entry. The rule: light data is
## loaded wholesale at boot, heavy assets (sprites, audio) per dungeon, through
## ResourceLoader.load_threaded_request during the entry fade. The dungeon itself is a
## separate Godot 3D scene ([member scene_path]).
class_name DungeonConfig
extends Resource

## Slug, and the base of this dungeon's translation keys.
@export var id: StringName

## The 3D scene exploration loads for this dungeon.
@export_file("*.tscn") var scene_path: String = ""

## The varieties a randomly composed rival group is drawn from. Their sprites are preloaded on
## entry, along with those of the special compositions and fixed groups
## ([method all_rival_species]).
@export var possible_species: Array[StringName] = []

## Scripted rivals and special factions present here, such as The Coal Vetch.
@export var special_rivals: Array[StringName] = []

## Ambient music, loaded with the rest of the dungeon's assets.
@export_file("*.ogg", "*.wav") var ambient_music: String = ""

@export_group("Rival spawns")

## S: the tiles where a rival group may appear. How many there are is the dungeon's S.
@export var spawn_points: Array[Vector3i] = []

## P: groups that appear on first entering the dungeon.
@export var initial_spawns: int = 0

## N: groups that appear every [member spawn_interval_turns] turns.
@export var spawns_per_wave: int = 0

## T: turns between two waves of [member spawns_per_wave] groups. 0 means no waves.
@export var spawn_interval_turns: int = 0

## X: the chance a spawned group is composed at random, from [member possible_species] and the
## bounds below; otherwise it is one of [member special_compositions]. The design doc keeps it
## between 50 % and 100 %.
@export_range(0.5, 1.0) var random_composition_chance: float = 1.0

## How many individuals a randomly composed group holds.
@export var group_size_min: int = 1
@export var group_size_max: int = 1

## The maximum DEN each individual of a random group is given, drawn in this range.
@export var member_max_den_min: int = 50
@export var member_max_den_max: int = 50

## The maximum ETH each individual of a random group is given, drawn in this range.
@export var member_max_eth_min: int = 50
@export var member_max_eth_max: int = 50

## The predefined compositions a spawn picks from when it is not drawn at random.
@export var special_compositions: Array[RivalGroupData] = []

## Groups whose composition AND position level design sets outside the spawn system — a tutorial
## rival, a boss. Each appears once, on its own [member RivalGroupData.tile], on first entry.
@export var fixed_groups: Array[RivalGroupData] = []


## Every variety a rival group can be made of here — random, special or fixed. What has to be
## preloaded on entry.
func all_rival_species() -> Array[StringName]:
	var out: Array[StringName] = possible_species.duplicate()
	for group in special_compositions + fixed_groups:
		for member in group.members:
			if member != null and not out.has(member.species_id):
				out.append(member.species_id)
	return out


## Translation key of the displayed name: DUNGEON_<ID>_NAME.
func name_key() -> String:
	return "DUNGEON_%s_NAME" % GameEnums.key_token(id)
