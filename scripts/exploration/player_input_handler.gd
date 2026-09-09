## Entrées du joueur en exploration : regard souris, rotation 90°, déplacement grille.
##
## Nœud enfant du Player. Modèle porté du proto Unity : le lacet visé = base rigide (par pas
## de 90° au clavier) + décalage de regard libre (delta souris relatif). Le corps rejoint cet
## angle en continu ([method PlayerController.set_yaw_target]) ; le pitch (regard vertical) est
## appliqué au [CameraRig] et recentré pendant/après une rotation.
##
## Curseur CAPTURÉ (caché, delta relatif — pas de recentrage) : c'est ce qui rend le regard
## fluide et évite que le curseur ne « saute » (contrairement à l'ancienne visée absolue).
## Échap libère le curseur (souris visible) pour cliquer l'UI ; recliquer dans la fenêtre le
## recapture.
##
## Comptage des tours : un pas fait avancer le tour (via [PlayerController.try_move]), et une
## rotation d'un quart de tour aussi — au clavier, ou dès que le regard libre s'écarte de
## [member commit_angle] de l'orientation de déplacement.
##
## Disarray : la doc ne fait plus d'exception pour le regard libre. Un geste de souris est
## dévié comme le reste, mais il ne DÉCOMPTE le piège que s'il enclenche une rotation — sinon
## on le purgerait en agitant le curseur, sans jamais dépenser de tour. Cf.
## [method _disarrayed_mouse] et [method _fold_offset].
class_name PlayerInputHandler
extends Node

@export var move_repeat_delay := 0.22
## Sensibilité souris, en degrés par pixel de déplacement.
@export var mouse_sensitivity := 0.14
@export var pitch_min := -60.0
@export var pitch_max := 60.0
## Degrés de dérive du regard libre au-delà desquels une rotation de 90° est VALIDÉE. Écart
## SIGNÉ par rapport à l'orientation de déplacement : regarder autour de soi et revenir ne
## valide rien (doc « Game Design / Dungeon Exploration »).
@export var commit_angle := 50.0

## Disarray : décalages applicables au geste de souris. Des quarts de tour, l'identité exclue —
## un geste dévié doit toujours partir ailleurs.
const DISARRAY_MOUSE_TURNS := [90.0, 180.0, 270.0]

## Temps sans le moindre mouvement de souris au bout duquel le GESTE en cours est clos. Le
## mouvement suivant en ouvre un neuf, et retire donc un nouveau mouvement de disarray.
const MOUSE_BURST_IDLE := 0.12
## Vitesse de recentrage du pitch après une rotation (deg/s).
@export var pitch_recenter_speed := 240.0

var _controller: PlayerController
var _rig: CameraRig
var _repeat_timer := 0.0

var _base_yaw := 0.0  # orientation rigide (multiples de 90°) = orientation de déplacement
var _yaw_offset := 0.0  # dérive du regard libre (souris) autour de la base
var _pitch := 0.0
var _recenter_pitch := false
var _initialised := false

# Geste de souris en cours (disarray) : ouverture, inactivité depuis le dernier événement, et
# décalage d'angle tiré à l'ouverture (0 = geste non dévié).
var _mouse_burst_open := false
var _mouse_burst_idle := 0.0
var _mouse_burst_turn := 0.0


func _ready() -> void:
	_controller = get_parent() as PlayerController
	_rig = get_parent().get_node_or_null("CameraRig") as CameraRig
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Regard souris (delta relatif) + bascule du curseur. Le regard libre n'agit qu'au repos
## (pas pendant un pas), comme dans le proto.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_set_mouse_captured(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED)
		return
	if _controller == null or _controller.input_locked:
		return
	if (
		event is InputEventMouseButton
		and event.pressed
		and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE
	):
		_set_mouse_captured(true)
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_apply_mouse_look(event.relative)


## Applique un delta souris relatif au regard (yaw libre + pitch). Le regard libre n'agit
## qu'au repos (pas pendant un pas), comme dans le proto.
func _apply_mouse_look(relative: Vector2) -> void:
	relative = _disarrayed_mouse(relative)
	if _controller.is_at_rest():
		# Souris à droite (relative.x > 0) => regarder à droite => lacet décroît.
		_yaw_offset -= relative.x * mouse_sensitivity
	if not _recenter_pitch:
		# Souris vers le haut (relative.y < 0) => regarder en haut => pitch croît.
		_pitch = clampf(_pitch - relative.y * mouse_sensitivity, pitch_min, pitch_max)


## Disarray appliqué au regard libre (doc « Level Design / Mechanisms », piège Disarray).
##
## On fait pivoter la DIRECTION du geste d'un quart de tour, sans toucher à son AMPLITUDE : le
## joueur parcourt la même distance, mais ailleurs. C'est ce qui évite de lui déclencher une
## rotation — donc un tour — qu'il n'a pas voulue : un petit geste reste un petit geste, et ne
## franchit pas [member commit_angle] davantage qu'il ne l'aurait fait sans le piège.
##
## Le décalage est tiré à l'OUVERTURE du geste (premier mouvement après un arrêt) et tenu
## jusqu'à sa fin : tourner le poignet en cours de geste ne change rien, s'arrêter puis repartir
## si. On CONSULTE la file sans la consommer — le décompte a lieu à la validation d'une rotation
## ([method _fold_offset]) : un geste qui n'enclenche rien reste dévié sans rien coûter, sinon
## le piège s'éliminerait en agitant le curseur.
func _disarrayed_mouse(relative: Vector2) -> Vector2:
	_mouse_burst_idle = 0.0
	if not _mouse_burst_open:
		_mouse_burst_open = true
		_mouse_burst_turn = 0.0
		if _controller.affliction.peek_move():
			_mouse_burst_turn = DISARRAY_MOUSE_TURNS[randi() % DISARRAY_MOUSE_TURNS.size()]
	if is_zero_approx(_mouse_burst_turn):
		return relative
	return relative.rotated(deg_to_rad(_mouse_burst_turn))


func _process(delta: float) -> void:
	if _controller == null:
		return
	if _mouse_burst_open:
		_mouse_burst_idle += delta
		if _mouse_burst_idle >= MOUSE_BURST_IDLE:
			_mouse_burst_open = false
	if not _initialised:
		_base_yaw = _controller.current_yaw_deg()
		_initialised = true
	if _controller.input_locked:
		return
	_handle_rotation()
	_handle_movement(delta)
	if _recenter_pitch:
		_pitch = move_toward(_pitch, 0.0, pitch_recenter_speed * delta)
		if absf(_pitch) < 0.5:
			_pitch = 0.0
			_recenter_pitch = false
	_fold_offset()
	_apply_look()


## Valide une rotation de 90° dès que le regard libre dépasse [member commit_angle] (≈ 50°,
## pas besoin d'atteindre 90°) : l'orientation de DÉPLACEMENT (et la mini-map) bascule alors,
## et un tour est compté. La tête reste où pointe la souris (continuité visuelle).
##
## C'est ICI que le regard libre décompte le disarray : une rotation enclenchée est un mouvement,
## un geste qui n'enclenche rien n'en est pas un. La déviation a déjà été appliquée au geste
## ([method _disarrayed_mouse]) à partir de cette même entrée de file, d'où le résultat ignoré.
func _fold_offset() -> void:
	while _yaw_offset >= commit_angle:
		_yaw_offset -= 90.0
		_base_yaw += 90.0
		_controller.affliction.consume_move()
		_controller.rotated_90()
	while _yaw_offset <= -commit_angle:
		_yaw_offset += 90.0
		_base_yaw -= 90.0
		_controller.affliction.consume_move()
		_controller.rotated_90()


func _handle_rotation() -> void:
	if not _controller.is_at_rest():
		return
	# Cohérent avec la souris (regarder à droite => lacet décroît) : E (droite) => -90.
	if Input.is_action_just_pressed("rotate_left"):
		_rotate_step(90.0)
	elif Input.is_action_just_pressed("rotate_right"):
		_rotate_step(-90.0)


## Rotation rigide de ±90° : snappe l'orientation courante au multiple de 90 le plus proche,
## ajoute l'angle, remet le regard libre à zéro et recentre le pitch. Compte un tour.
func _rotate_step(angle: float) -> void:
	# Disarray : une part des rotations est inversée (« if rotation, another rotation »).
	if _controller.affliction.consume_move():
		angle = -angle
	var current := _base_yaw + _yaw_offset
	current = roundf(current / 90.0) * 90.0
	_base_yaw = current + angle
	_yaw_offset = 0.0
	_recenter_pitch = true
	_controller.rotated_90()


func _handle_movement(delta: float) -> void:
	var axis := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if axis == Vector2.ZERO:
		_repeat_timer = 0.0  # 1er pas immédiat au prochain appui
		return
	_repeat_timer -= delta
	if not _controller.is_at_rest() or _repeat_timer > 0.0:
		return
	var dir: Vector3
	if absf(axis.y) >= absf(axis.x):
		dir = Vector3.FORWARD if axis.y < 0.0 else Vector3.BACK
	else:
		dir = Vector3.RIGHT if axis.x > 0.0 else Vector3.LEFT
	_controller.try_move(dir)
	_repeat_timer = move_repeat_delay


func _apply_look() -> void:
	_controller.set_yaw_target(_base_yaw + _yaw_offset)  # orientation VISUELLE (continue)
	_controller.set_move_yaw(_base_yaw)  # orientation DÉPLACEMENT (cardinale)
	if _rig != null:
		_rig.set_pitch(_pitch)


func _set_mouse_captured(captured: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE
