## The screen of Slick Merchant's Run Away quick-time event: a bar with a zone, a sweeping marker,
## and a prompt. Minimal on purpose; the rules are in `qte.gd` and this only keeps the clock and
## draws.
##
## [method play] is a coroutine returning whether the attempt succeeded. Accept (or a click) is the
## press. The first frame is not armed yet: the key that chose Run Away in the menu may still be
## arriving, and it must not count as the press.
##
## No `class_name`, see CLAUDE.md: preloaded.
extends Control

const Qte := preload("res://scripts/encounter/qte.gd")

const BAR_SIZE := Vector2(560.0, 36.0)
## Seconds the verdict stays up before the overlay goes.
const VERDICT_SECONDS := 0.7

signal _done(outcome)

var _qte
var _elapsed := 0.0
var _armed := false
var _running := false
var _verdict := ""
var _prompt: Label


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_prompt = Label.new()
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.set_anchors_preset(Control.PRESET_CENTER_TOP)
	add_child(_prompt)
	set_process(false)


## Plays `qte` for `who`'s Run Away. The overlay frees itself afterwards.
func play(qte, who_name: String) -> bool:
	_qte = qte
	_elapsed = 0.0
	_armed = false
	_verdict = ""
	_prompt.text = tr("UI_QTE_PROMPT") % who_name
	_prompt.position = Vector2(0.0, size.y * 0.5 - BAR_SIZE.y - 48.0)
	_prompt.size = Vector2(size.x, 32.0)
	_running = true
	set_process(true)
	await get_tree().process_frame
	_armed = true
	var outcome = await _done
	_running = false
	var ok: bool = Qte.succeeded(outcome)
	_verdict = tr("UI_QTE_PASSED" if ok else "UI_QTE_FAILED")
	_prompt.text = _verdict
	queue_redraw()
	await get_tree().create_timer(VERDICT_SECONDS).timeout
	queue_free()
	return ok


func _process(delta: float) -> void:
	if not _running or not _armed:
		return
	_elapsed += delta
	if _elapsed >= _qte.time_limit:
		_done.emit(Qte.Outcome.TIMEOUT)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not _running or not _armed:
		return
	if event is InputEventMouseButton and event.pressed:
		accept_event()
		_done.emit(_qte.evaluate(_elapsed))


func _input(event: InputEvent) -> void:
	if _running and _armed and event.is_action_pressed("ui_accept") and not event.is_echo():
		get_viewport().set_input_as_handled()
		_done.emit(_qte.evaluate(_elapsed))


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.04, 0.06, 0.6))
	if _qte == null:
		return
	var origin := (size - BAR_SIZE) * 0.5
	draw_rect(Rect2(origin, BAR_SIZE), Color(0.2, 0.2, 0.26))
	var zone_w: float = _qte.zone_width * BAR_SIZE.x
	var zone_x: float = origin.x + _qte.zone_center * BAR_SIZE.x - zone_w * 0.5
	draw_rect(Rect2(zone_x, origin.y, zone_w, BAR_SIZE.y), Color(0.35, 0.75, 0.45))
	var marker_x: float = origin.x + _qte.marker_at(_elapsed) * BAR_SIZE.x
	draw_rect(Rect2(marker_x - 3.0, origin.y - 8.0, 6.0, BAR_SIZE.y + 16.0), Color(1, 1, 1))
