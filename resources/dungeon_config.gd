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

## Species that can appear here. Only their sprites are preloaded on entry.
@export var possible_species: Array[StringName] = []

## Scripted rivals and special factions present here, such as The Coal Vetch.
@export var special_rivals: Array[StringName] = []

## Ambient music, loaded with the rest of the dungeon's assets.
@export_file("*.ogg", "*.wav") var ambient_music: String = ""


## Translation key of the displayed name: DUNGEON_<ID>_NAME.
func name_key() -> String:
	return "DUNGEON_%s_NAME" % GameEnums.key_token(id)
