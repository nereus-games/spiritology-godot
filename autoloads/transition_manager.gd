## Transitions entre scènes et fondus (autoload `TransitionManager`).
##
## Gère les fondus et le changement de scène principale. Important pour l'archi :
## les rencontres ne passent PAS par un changement de scène — elles sont chargées en
## OVERLAY additif par-dessus l'exploration (voir [method open_encounter]).
extends CanvasLayer

const FADE_TIME := 0.35

var _fade: ColorRect


func _ready() -> void:
	# Squelette : le ColorRect plein écran est créé par code si la scène ne le fournit pas.
	_fade = get_node_or_null("Fade")
	if _fade == null:
		_fade = ColorRect.new()
		_fade.color = Color.BLACK
		_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
		_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_fade)
	_fade.modulate.a = 0.0


## Fondu au noir → change la scène principale → fondu d'ouverture.
func change_scene(scene_path: String) -> void:
	await fade_out()
	get_tree().change_scene_to_file(scene_path)
	await fade_in()


func fade_out() -> Signal:
	var tween := create_tween()
	tween.tween_property(_fade, "modulate:a", 1.0, FADE_TIME)
	return tween.finished


func fade_in() -> Signal:
	var tween := create_tween()
	tween.tween_property(_fade, "modulate:a", 0.0, FADE_TIME)
	return tween.finished


const ENCOUNTER_SCENE := "res://scenes/encounter/encounter.tscn"

signal encounter_finished(result: StringName)

var _encounter: CanvasLayer

## CanvasLayer de l'exploration masqués le temps de la rencontre, à rallumer ensuite.
var _hidden_hud: Array[CanvasLayer] = []


## Ouvre une rencontre en OVERLAY additif sous `root`, sans décharger l'exploration :
## la scène d'exploration est mise en pause (process_mode = DISABLED) et reste visible
## (floutée) derrière l'UI 2D. `player_ids`/`rival_ids` = slugs d'espèces.
## `rival_states` (optionnel, parallèle à `rival_ids`) : état de carte de chaque rival, sous
## la forme `{"den": int, "max_den": int}`. Le maximum vient du LEVEL DESIGN (réglé donjon par
## donjon) et le courant reporte les dégâts subis en exploration (chute). Entrée vide/absente =
## le rival part sur ses valeurs par défaut.
func open_encounter(
	player_ids: Array, rival_ids: Array, completed: Dictionary = {}, rival_states: Array = []
) -> void:
	if _encounter != null:
		return  # une rencontre est déjà ouverte
	var exploration := get_tree().current_scene
	if exploration:
		exploration.process_mode = Node.PROCESS_MODE_DISABLED
		_hide_scene_hud(exploration)

	_encounter = load(ENCOUNTER_SCENE).instantiate()
	get_tree().root.add_child(_encounter)
	_encounter.finished.connect(_on_encounter_finished.bind(exploration))
	_encounter.begin(player_ids, rival_ids, completed, rival_states)


func _on_encounter_finished(result: StringName, exploration: Node) -> void:
	if is_instance_valid(_encounter):
		_encounter.queue_free()
	_encounter = null
	if is_instance_valid(exploration):
		exploration.process_mode = Node.PROCESS_MODE_INHERIT
		_restore_scene_hud()
	encounter_finished.emit(result)


## Masque les CanvasLayer de la scène d'exploration le temps de la rencontre.
##
## L'exploration reste chargée et visible derrière l'overlay, mais son HUD, lui, doit
## disparaître : il vit sur son propre CanvasLayer, donc mettre l'exploration en pause ne
## le masque pas, et il se superposerait à l'UI de rencontre (qui n'en montre aucun dans
## le mockup). On ne mémorise que ceux réellement visibles, pour ne pas rallumer au
## retour un HUD qui était déjà caché.
func _hide_scene_hud(scene: Node) -> void:
	_hidden_hud.clear()
	for node in scene.find_children("*", "CanvasLayer", true, false):
		var layer := node as CanvasLayer
		if layer.visible:
			layer.visible = false
			_hidden_hud.append(layer)


func _restore_scene_hud() -> void:
	for layer in _hidden_hud:
		if is_instance_valid(layer):
			layer.visible = true
	_hidden_hud.clear()
