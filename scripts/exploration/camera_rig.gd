## Tête de caméra du donjon : regard vertical (pitch) + micro-bruit d'inactivité + FOV.
##
## Le lacet (yaw) est porté par le [PlayerController] parent (modèle base rigide + regard libre
## souris, piloté par [PlayerInputHandler]). Ce rig n'applique QUE le pitch, reçu via
## [method set_pitch] ; le regard horizontal n'est plus géré ici (fini la visée absolue au
## curseur et le recentrage du curseur, qui empêchait de cliquer l'UI).
##
## Gère aussi le FOV : le FOV vertical est rogné automatiquement sur les écrans larges pour que
## le FOV HORIZONTAL ne dépasse jamais [member max_hfov_deg].
##
## Hiérarchie attendue : Player (yaw marche) > CameraRig (ce script) > Camera3D. Le rig est
## posé à hauteur des yeux du duo ([constant DungeonManager.EYE_HEIGHT] = 0.6 m dans
## `player.tscn`), donc SOUS le haut des murs (1 m) : on ne voit jamais par-dessus.
class_name CameraRig
extends Node3D

@export var pitch_min_deg := -60.0
@export var pitch_max_deg := 60.0

@export_group("Field of View")
## FOV vertical visé (sur un écran étroit, c'est celui-ci qui s'applique tel quel).
@export_range(30.0, 110.0, 1.0) var base_fov := 60.0
## Plafond du FOV horizontal. Au-delà, le FOV vertical est rogné pour compenser.
@export_range(60.0, 140.0, 1.0) var max_hfov_deg := 90.0
## Plancher du FOV vertical : sur un ultra-large, tenir le plafond horizontal coûterait tant
## de vertical qu'on ne verrait plus ni le sol ni le haut des murs.
@export_range(20.0, 90.0, 1.0) var min_fov := 45.0

@export_group("Idle Noise")
@export var idle_amplitude := 0.015
@export var idle_frequency := 0.6
@export var idle_delay := 0.6

var _pitch_deg := 0.0

@onready var _camera: Camera3D = get_node_or_null("Camera3D")

var _player: PlayerController
var _noise := FastNoiseLite.new()
var _noise_t := 0.0
var _idle_timer := 0.0
var _cam_base_pos := Vector3.ZERO


func _ready() -> void:
	_player = get_parent() as PlayerController
	_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	if _camera:
		_cam_base_pos = _camera.position
	var vp := get_viewport()
	if vp:
		vp.size_changed.connect(_update_fov)
	_update_fov()


## Regard vertical, en degrés (positif = vers le haut). Borné, appliqué immédiatement.
func set_pitch(deg: float) -> void:
	_pitch_deg = clampf(deg, pitch_min_deg, pitch_max_deg)
	rotation.x = deg_to_rad(_pitch_deg)


## Roulis (inclinaison latérale) de la vue, en degrés — simule la perte d'équilibre sur un
## pont étroit. 0 = horizon droit.
func set_roll(deg: float) -> void:
	rotation.z = deg_to_rad(deg)


func _process(delta: float) -> void:
	_update_idle_noise(delta)


## Rogne le FOV vertical pour que le FOV horizontal reste sous [member max_hfov_deg].
func _update_fov() -> void:
	if _camera == null:
		return
	var vp := get_viewport()
	if vp == null:
		return
	var rect := vp.get_visible_rect().size
	if rect.x <= 0.0 or rect.y <= 0.0:
		return
	var aspect := rect.x / rect.y
	var hfov := rad_to_deg(2.0 * atan(tan(deg_to_rad(base_fov) * 0.5) * aspect))
	if hfov <= max_hfov_deg:
		_camera.fov = base_fov
	else:
		var clamped := rad_to_deg(2.0 * atan(tan(deg_to_rad(max_hfov_deg) * 0.5) / aspect))
		_camera.fov = maxf(clamped, minf(min_fov, base_fov))


func _update_idle_noise(delta: float) -> void:
	if _camera == null:
		return
	var at_rest := _player == null or _player.is_at_rest()
	_idle_timer = _idle_timer + delta if at_rest else 0.0
	var intensity := 1.0 if _idle_timer > idle_delay else 0.0
	_noise_t += delta * idle_frequency
	var offset := (
		Vector3(_noise.get_noise_2d(_noise_t, 0.0), _noise.get_noise_2d(0.0, _noise_t), 0.0)
		* idle_amplitude
		* intensity
	)
	_camera.position = _camera.position.lerp(_cam_base_pos + offset, delta * 8.0)
