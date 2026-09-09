## Configuration d'un donjon.
##
## Décrit ce qu'un donjon peut faire apparaître, afin de précharger les bons assets
## (sprites/audio) à l'entrée — règle d'archi : données = tout au boot, assets lourds
## = par donjon, via ResourceLoader.load_threaded_request pendant le fondu d'entrée.
## Le donjon lui-même est une scène 3D Godot indépendante (champ [member scene_path]).
class_name DungeonConfig
extends Resource

## Identifiant slug du donjon (ex. "coal_vetch_mines"). Base des clés de trad.
@export var id: StringName

## Scène 3D du donjon à charger dans l'exploration.
@export_file("*.tscn") var scene_path: String = ""

## Espèces susceptibles d'apparaître ici (slugs). Sert à précharger uniquement
## les sprites de ces espèces à l'entrée du donjon.
@export var possible_species: Array[StringName] = []

## Rivaux scriptés / factions spéciales (ex. The Coal Vetch) présents dans le donjon.
@export var special_rivals: Array[StringName] = []

## Musique d'ambiance du donjon (chemin, chargé contextuellement).
@export_file("*.ogg", "*.wav") var ambient_music: String = ""


## Clé de traduction du nom affichable. Convention : DUNGEON_<ID_MAJ>_NAME.
func name_key() -> String:
	return "DUNGEON_%s_NAME" % GameEnums.key_token(id)
