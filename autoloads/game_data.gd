## The game's data registry (autoload `GameData`).
##
## Loads the entire LIGHT database at boot — every species, ability, talent, object and
## dungeon. The cost is invisible once, and it buys freedom from micro-freezes in play.
## Heavy assets (sprites, audio) are NEVER loaded here; they are loaded per dungeon.
## Read-only afterwards, through the getters.
extends Node

const SPECIES_DIR := "res://data/species/"
const ABILITIES_DIR := "res://data/abilities/"
const DUNGEONS_DIR := "res://data/dungeons/"
const OBJECTS_DIR := "res://data/objects/"

var _species: Dictionary = {}  ## StringName id -> SpeciesData
var _abilities: Dictionary = {}  ## StringName id -> AbilityData
var _talents: Dictionary = {}  ## StringName id -> TalentData
var _dungeons: Dictionary = {}  ## StringName id -> DungeonConfig
var _objects: Dictionary = {}  ## StringName id -> ObjectData


func _ready() -> void:
	_load_dir(SPECIES_DIR)
	# abilities/ holds AbilityData AND TalentData — in the design doc they are one database,
	# told apart by a Type column. Routed to the right registry by resource type.
	_load_dir(ABILITIES_DIR)
	_load_dir(DUNGEONS_DIR)
	_load_dir(OBJECTS_DIR)
	print(
		(
			"[GameData] loaded %d species, %d abilities, %d talents, %d dungeons, %d objects."
			% [
				_species.size(),
				_abilities.size(),
				_talents.size(),
				_dungeons.size(),
				_objects.size()
			]
		)
	)


## Loads every .tres in a directory into the registry matching its type, keyed by `id`.
func _load_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		push_warning("[GameData] directory not found: %s (empty for now?)" % path)
		return
	for file_name in dir.get_files():
		# Exported builds turn .tres into .tres.remap.
		if not (file_name.ends_with(".tres") or file_name.ends_with(".tres.remap")):
			continue
		var res_path := path + file_name.trim_suffix(".remap")
		var res: Resource = load(res_path)
		if res == null or not ("id" in res):
			push_warning("[GameData] skipping invalid resource: %s" % res_path)
			continue
		_registry_for(res)[res.id] = res


## The registry a resource belongs in, by type.
func _registry_for(res: Resource) -> Dictionary:
	if res is SpeciesData:
		return _species
	if res is TalentData:
		return _talents
	if res is AbilityData:
		return _abilities
	if res is DungeonConfig:
		return _dungeons
	if res is ObjectData:
		return _objects
	push_warning("[GameData] unhandled resource type: %s" % res)
	return {}


func species(id: StringName) -> SpeciesData:
	return _species.get(id)


func ability(id: StringName) -> AbilityData:
	return _abilities.get(id)


func talent(id: StringName) -> TalentData:
	return _talents.get(id)


func dungeon(id: StringName) -> DungeonConfig:
	return _dungeons.get(id)


func object(id: StringName) -> ObjectData:
	return _objects.get(id)


func all_species() -> Array:
	return _species.values()
