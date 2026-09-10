## Player input during exploration: mouse look, 90-degree turns, grid movement.
##
## A child node of the Player. The model is ported from the prototype: the target yaw is a rigid
## base (90-degree steps from the keyboard) plus a free-look offset (relative mouse delta). The
## body continuously catches up to that angle ([method PlayerController.set_yaw_target]), while
## pitch is applied to the [CameraRig] and recentred during and after a turn.
##
## The cursor is CAPTURED — hidden, relative deltas, no recentring — which is what makes looking
## around smooth and keeps the cursor from jumping, as it did under the old absolute aiming. Esc
## releases the cursor so the UI can be clicked; clicking back in the window recaptures it.
##
## Turn counting: a step advances the turn (through [PlayerController.try_move]), and so does a
## quarter turn — from the keyboard, or as soon as free look drifts [member commit_angle] away
## from the movement facing.
##
## Disarray: the design doc no longer makes an exception for free look. A mouse gesture is
## deflected like anything else, but it only COUNTS the trap down if it commits a turn —
## otherwise the trap could be drained by waggling the cursor, without ever spending a turn. See
## [method _disarrayed_mouse] and [method _fold_offset].
class_name PlayerInputHandler
extends Node

@export var move_repeat_delay := 0.22
## Mouse sensitivity, in degrees per pixel moved.
@export var mouse_sensitivity := 0.14
@export var pitch_min := -60.0
@export var pitch_max := 60.0
## How far free look has to drift, in degrees, before a 90-degree turn is COMMITTED. A SIGNED
## offset from the movement facing, so looking around and coming back commits nothing.
@export var commit_angle := 50.0

## Disarray: the offsets a mouse gesture can be given. Quarter turns, identity excluded — a
## deflected gesture must always go somewhere else.
const DISARRAY_MOUSE_TURNS := [90.0, 180.0, 270.0]

## How long without any mouse motion closes the GESTURE in progress. The next motion opens a
## fresh one, and so takes another move off the disarray queue.
const MOUSE_BURST_IDLE := 0.12
## How fast pitch recentres after a turn, in degrees per second.
@export var pitch_recenter_speed := 240.0

var _controller: PlayerController
var _rig: CameraRig
var _repeat_timer := 0.0

var _base_yaw := 0.0  # the rigid facing (multiples of 90), which is the movement facing
var _yaw_offset := 0.0  # free-look drift around that base
var _pitch := 0.0
var _recenter_pitch := false
var _initialised := false

# The mouse gesture in progress, for disarray: whether one is open, how long since the last
# event, and the angle offset rolled when it opened (0 means undeflected).
var _mouse_burst_open := false
var _mouse_burst_idle := 0.0
var _mouse_burst_turn := 0.0


func _ready() -> void:
	_controller = get_parent() as PlayerController
	_rig = get_parent().get_node_or_null("CameraRig") as CameraRig
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Mouse look, from relative deltas, plus toggling the cursor.
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


## Applies a relative mouse delta to the look — free yaw and pitch. Free look only acts at rest,
## never mid-step, as in the prototype.
func _apply_mouse_look(relative: Vector2) -> void:
	relative = _disarrayed_mouse(relative)
	if _controller.is_at_rest():
		# Mouse right (relative.x > 0) means looking right, which decreases yaw.
		_yaw_offset -= relative.x * mouse_sensitivity
	if not _recenter_pitch:
		# Mouse up (relative.y < 0) means looking up, which increases pitch.
		_pitch = clampf(_pitch - relative.y * mouse_sensitivity, pitch_min, pitch_max)


## Disarray applied to free look (the design doc's Disarray trap).
##
## The gesture's DIRECTION is rotated a quarter turn, leaving its MAGNITUDE alone: the player
## covers the same distance, but somewhere else. That is what avoids triggering a turn — and so
## a game turn — they never asked for: a small gesture stays a small gesture, and crosses
## [member commit_angle] no more readily than it would have without the trap.
##
## The offset is rolled when the gesture OPENS, on the first motion after a pause, and held until
## it ends: turning your wrist mid-gesture changes nothing, stopping and starting again does. The
## queue is PEEKED rather than consumed — the count moves when a turn is committed (see
## [method _fold_offset]) — so a gesture that commits nothing stays deflected but costs nothing,
## since otherwise the trap could be drained by waggling the cursor.
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


## Commits a 90-degree turn as soon as free look drifts past [member commit_angle] — about 50
## degrees, so there is no need to reach 90. The MOVEMENT facing (and the mini-map) swings over,
## and a turn is counted. The head stays where the mouse points, for visual continuity.
##
## This is where free look counts disarray down: a committed turn is a move, a gesture that
## commits nothing is not. The deflection was already applied to the gesture
## ([method _disarrayed_mouse]) from this same queue entry, hence the ignored result here.
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
	# Consistent with the mouse, where looking right decreases yaw: E (right) gives -90.
	if Input.is_action_just_pressed("rotate_left"):
		_rotate_step(90.0)
	elif Input.is_action_just_pressed("rotate_right"):
		_rotate_step(-90.0)


## A rigid turn of plus or minus 90 degrees: snaps the current facing to the nearest multiple of
## 90, adds the angle, zeroes free look and recentres pitch. Counts as a turn.
func _rotate_step(angle: float) -> void:
	# Disarray: a share of turns is reversed ("if rotation, another rotation").
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
		_repeat_timer = 0.0  # so the next press steps immediately
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
	_controller.set_yaw_target(_base_yaw + _yaw_offset)  # the VISUAL facing, continuous
	_controller.set_move_yaw(_base_yaw)  # the MOVEMENT facing, cardinal
	if _rig != null:
		_rig.set_pitch(_pitch)


func _set_mouse_captured(captured: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE
