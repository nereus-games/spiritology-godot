## The boot scene: the first node loaded (main_scene).
##
## Sets the language, checks whether a save exists, then moves on to the title screen. The static
## data is already loaded by the [GameData] autoload, which initialises before this scene.
extends Node

## The test-scenario selection screen: the entry point while there is no title screen. It picks
## which exploration scenario to launch. Temporary.
const PLAY_SCENE := "res://scenes/dev/scenario_select.tscn"


func _ready() -> void:
	_init_locale()
	var has_save := SaveSystem.has_save()
	print("[Boot] locale=%s, save=%s" % [TranslationServer.get_locale(), has_save])
	# TODO: move on to title_screen.tscn once the title screen exists. For now, F5 lands in the
	# test-scenario selection screen.
	TransitionManager.change_scene(PLAY_SCENE)


## Uses the system language when it is supported, and falls back to EN otherwise.
func _init_locale() -> void:
	var system_locale := OS.get_locale_language()
	var supported := TranslationServer.get_loaded_locales()
	if system_locale in supported:
		TranslationServer.set_locale(system_locale)
	else:
		TranslationServer.set_locale("en")
