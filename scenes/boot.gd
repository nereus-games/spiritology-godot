## Scène d'amorçage. Premier nœud chargé (main_scene).
##
## Initialise la langue, vérifie la présence d'une sauvegarde, puis enchaîne vers
## l'écran-titre. Les données statiques sont déjà chargées par l'autoload [GameData]
## (qui s'initialise avant cette scène).
extends Node

## Écran de sélection des scénarios de test : point d'entrée tant que l'écran-titre n'existe
## pas (choisit quel scénario d'exploration lancer). Temporaire.
const PLAY_SCENE := "res://scenes/dev/scenario_select.tscn"


func _ready() -> void:
	_init_locale()
	var has_save := SaveSystem.has_save()
	print("[Boot] langue=%s, sauvegarde=%s" % [TranslationServer.get_locale(), has_save])
	# TODO: enchaîner vers title_screen.tscn quand l'écran-titre existera ; pour l'instant
	# on entre dans l'écran de sélection des scénarios de test (F5).
	TransitionManager.change_scene(PLAY_SCENE)


## Applique la langue système si elle est supportée, sinon le fallback EN.
func _init_locale() -> void:
	var system_locale := OS.get_locale_language()
	var supported := TranslationServer.get_loaded_locales()
	if system_locale in supported:
		TranslationServer.set_locale(system_locale)
	else:
		TranslationServer.set_locale("en")
