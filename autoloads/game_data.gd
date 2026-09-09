## Registre central des données du jeu (autoload `GameData`).
##
## Charge AU BOOT toute la base de données LÉGÈRE : les .tres de species/abilities/talents
## (noms, stats, clés de trad, faiblesses, références). Coût invisible, zéro micro-freeze
## en jeu. Les assets lourds (sprites, audio) ne sont JAMAIS chargés ici — ils le sont
## par donjon. Accès en lecture seule via les getters.
extends Node

const SPECIES_DIR := "res://data/species/"
const ABILITIES_DIR := "res://data/abilities/"
const DUNGEONS_DIR := "res://data/dungeons/"
const OBJECTS_DIR := "res://data/objects/"

var _species: Dictionary = {}    ## StringName id -> SpeciesData
var _abilities: Dictionary = {}  ## StringName id -> AbilityData
var _talents: Dictionary = {}    ## StringName id -> TalentData (sous-ensemble Type=Talent)
var _dungeons: Dictionary = {}   ## StringName id -> DungeonConfig
var _objects: Dictionary = {}    ## StringName id -> ObjectData

func _ready() -> void:
	_load_dir(SPECIES_DIR)
	# Le dossier abilities/ contient AbilityData ET TalentData (générés depuis Notion).
	# On les route vers le bon registre selon le type de la ressource.
	_load_dir(ABILITIES_DIR)
	_load_dir(DUNGEONS_DIR)
	_load_dir(OBJECTS_DIR)
	print("[GameData] %d espèces, %d capacités, %d talents, %d donjons, %d objets chargés." % [
		_species.size(), _abilities.size(), _talents.size(), _dungeons.size(), _objects.size()])

## Charge tous les .tres d'un dossier et range chaque ressource dans le registre
## correspondant à son type, indexée par son `id`.
func _load_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		push_warning("[GameData] dossier introuvable : %s (vide pour l'instant ?)" % path)
		return
	for file_name in dir.get_files():
		# En export, les .tres deviennent .tres.remap ; on normalise.
		if not (file_name.ends_with(".tres") or file_name.ends_with(".tres.remap")):
			continue
		var res_path := path + file_name.trim_suffix(".remap")
		var res: Resource = load(res_path)
		if res == null or not ("id" in res):
			push_warning("[GameData] ressource invalide ignorée : %s" % res_path)
			continue
		_registry_for(res)[res.id] = res

## Renvoie le dictionnaire-registre adapté au type d'une ressource.
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
	push_warning("[GameData] type de ressource non géré : %s" % res)
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
