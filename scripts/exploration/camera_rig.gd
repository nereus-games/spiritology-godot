## The dungeon's camera head: vertical look (pitch), idle micro-noise, and FOV.
##
## Yaw belongs to the parent [PlayerController] — the rigid base plus mouse free look, driven by
## [PlayerInputHandler]. This rig applies ONLY pitch, received through [method set_pitch].
## Horizontal look is no longer handled here: absolute cursor aiming and cursor recentring are
## gone, since they made the UI unclickable.
##
## It also handles FOV: the vertical FOV is trimmed automatically on wide screens so the
## HORIZONTAL FOV never exceeds [member max_hfov_deg].
##
## Expected hierarchy: Player (walking yaw) > CameraRig (this script) > Camera3D. The rig sits at
## the duo's eye height ([constant DungeonManager.EYE_HEIGHT] = 0.6 m in `player.tscn`), and so
## BELOW the top of the walls (1 m): you never see over them.
class_name CameraRig
extends Node3D

@export var pitch_min_deg := -60.0
@export var pitch_max_deg := 60.0

@export_group("Field of View")
## The target vertical FOV. On a narrow screen it applies as-is.
@export_range(30.0, 110.0, 1.0) var base_fov := 60.0
## Ceiling on the horizontal FOV. Past it, the vertical FOV is trimmed to compensate.
@export_range(60.0, 140.0, 1.0) var max_hfov_deg := 90.0
## Floor on the vertical FOV: on an ultra-wide screen, holding the horizontal ceiling would cost
## so much vertical that neither the ground nor the tops of the walls would be visible.
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


## Vertical look, in degrees, positive upwards. Clamped, and applied at once.
func set_pitch(deg: float) -> void:
	_pitch_deg = clampf(deg, pitch_min_deg, pitch_max_deg)
	rotation.x = deg_to_rad(_pitch_deg)


## Roll, the sideways tilt of the view, in degrees — this is losing your footing on a narrow
## bridge. 0 keeps the horizon level.
func set_roll(deg: float) -> void:
	rotation.z = deg_to_rad(deg)


func _process(delta: float) -> void:
	_update_idle_noise(delta)


## Trims the vertical FOV to keep the horizontal one under [member max_hfov_deg].
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
