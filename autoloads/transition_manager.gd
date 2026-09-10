## Scene changes and fades (autoload `TransitionManager`).
##
## Architecturally the point to know: an encounter is NOT a scene change. It loads as an
## additive OVERLAY on top of exploration, which stays loaded and paused behind it — see
## [method open_encounter].
extends CanvasLayer

const FADE_TIME := 0.35

var _fade: ColorRect


func _ready() -> void:
	# Built in code when the scene does not provide one.
	_fade = get_node_or_null("Fade")
	if _fade == null:
		_fade = ColorRect.new()
		_fade.color = Color.BLACK
		_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
		_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_fade)
	_fade.modulate.a = 0.0


## Fade to black, swap the main scene, fade back in.
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

## Exploration CanvasLayers hidden for the duration of an encounter, to restore after.
var _hidden_hud: Array[CanvasLayer] = []


## Opens an encounter as an additive overlay, without unloading exploration: the
## exploration scene is paused (process_mode = DISABLED) and stays visible behind the 2D UI.
##
## `rival_states` runs parallel to `rival_ids` and carries each rival's state on the map,
## as `{"den": int, "max_den": int}`. The maximum is a LEVEL DESIGN setting, tuned per
## dungeon; the current value carries over damage taken while exploring, such as a fall.
## A missing or empty entry means the rival starts on its own defaults.
func open_encounter(
	player_ids: Array, rival_ids: Array, completed: Dictionary = {}, rival_states: Array = []
) -> void:
	if _encounter != null:
		return  # one is already open
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


## Hides the exploration scene's CanvasLayers for the duration of an encounter.
##
## Exploration stays loaded and visible behind the overlay, but its HUD must not be: a
## CanvasLayer is not affected by pausing the scene, so the HUD would sit on top of the
## encounter UI, which shows none. Only the layers that were actually visible are
## remembered, so that returning does not switch on a HUD that was already hidden.
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
