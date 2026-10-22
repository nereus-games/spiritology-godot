## The assembly desk of one encyclopaedia page, as a screen ("Page Assembly / Fragment
## Manipulation"): a view over [code]puzzle_desk.gd[/code], through
## [code]encyclopaedia_assembly_logic.gd[/code], and over [GameSession]'s model.
##
## Two sections, as in the doc: the manipulation area, which takes most of the display and shows
## its grid only while a fragment is held, and the new fragment area, set apart on the right with
## no grid, where fresh fragments lie inert. A held fragment moves a tile at a time, but its
## drawing glides there; it turns a quarter either way; one that would hover over another is
## refused, and shakes. After every request the screen tells the session what became of the
## page (arranged count, destroyed fragments, vanished parasites, completion) and parks the
## layout in the page's `puzzle_state`, so that leaving and coming back keeps it.
##
## Not tied to the encyclopaedia screen: it is a scene that can be instanced over anything.
## Set [member species_id] (and [member forlorn]) before it enters the tree; [signal closed] says
## the player left. Run as a scene of its own, leaving goes back to the dev scenario picker.
##
## Controls (input actions, so keyboard and gamepad alike): the arrows or D-pad move the cursor
## between fragments, or the held fragment one tile; Accept picks up and puts down; Cancel puts
## down, or leaves; `assembly_rotate_left` / `assembly_rotate_right` (Q / E, shoulder buttons)
## turn the held fragment; `assembly_stash` (Backspace, Y) sends a lone one back to the new
## fragment area; Tab and Shift+Tab (`ui_focus_next` / `ui_focus_prev`) cycle the cursor.
##
## Sounds are only a hook: [signal sound_requested] names them (`parasite_snicker`, `snap`,
## `refused`, `page_assembled`) and nothing plays them yet.
##
## No `class_name` (the CLI class-cache trap).
extends Control

const Logic := preload("res://scripts/ui/encyclopaedia_assembly_logic.gd")
const Art := preload("res://scripts/ui/encyclopaedia_assembly_art.gd")
const FragmentView := preload("res://scripts/ui/encyclopaedia_assembly_fragment.gd")
const Results := preload("res://scripts/encyclopaedia/puzzle_results.gd")
const Fragment := preload("res://scripts/encyclopaedia/puzzle_fragment.gd")

const RETURN_SCENE := "res://scenes/dev/scenario_select.tscn"

## Seconds a one-tile glide takes; the repeat interval is longer, so a held key never queues up.
const GLIDE_SECONDS := 0.09
const REPEAT_DELAY := 0.28
const REPEAT_INTERVAL := 0.1
const NOTICE_SECONDS := 3.5
const NEW_AREA_WIDTH := 264.0
const AREA_GAP := 14.0

const COLOR_BACKGROUND := Color(0.07, 0.07, 0.1)
const COLOR_DESK := Color(0.105, 0.115, 0.16)
const COLOR_DESK_EDGE := Color(0.3, 0.34, 0.46)
const COLOR_GRID := Color(0.6, 0.7, 0.95)
const COLOR_NEW := Color(0.2, 0.15, 0.115)
const COLOR_NEW_EDGE := Color(0.72, 0.52, 0.3)
const COLOR_DIM := Color(0.62, 0.65, 0.72)
const COLOR_GOLD := Color(0.95, 0.85, 0.45)

## The sound hook: nothing is played, see the class docs.
signal sound_requested(sound: StringName)
signal closed

## The species whose page is on the desk.
var species_id: StringName = &""
## Whether it is the species' Forlorn page.
var forlorn: bool = false
## The decisions, an `encyclopaedia_assembly_logic.gd` instance.
var logic: Variant

var _views := {}  # id -> FragmentView
var _stage: Control
var _layer: Control
var _body: Control
var _new_label: Label
var _summary: Label
var _notice: Label
var _hint: Label
var _desk_area := Rect2()
var _new_area := Rect2()
var _new_inner := Rect2()
var _desk_rect := Rect2()
var _tile_px: float = 1.0
var _grid_alpha: float = 0.0
var _grid_tween: Tween
var _notice_tween: Tween
var _picture: Texture2D
var _decoy: Texture2D
var _held := Vector2i.ZERO
var _hold_time: float = 0.0
var _next_fire: float = 0.0
var _handling_left: float = 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	if species_id == &"":
		species_id = &"kalilk"
	logic = Logic.open(
		species_id,
		forlorn,
		GameSession.puzzle_state(species_id, forlorn),
		GameSession.true_fragments(species_id, forlorn),
		GameSession.parasitic_fragments(species_id, forlorn),
		GameSession.arranged_fragments(species_id, forlorn),
		GameSession.is_page_complete(species_id, forlorn)
	)
	_picture = Art.picture(logic.page_seed, false)
	_decoy = Art.picture(logic.page_seed, true)
	logic.ensure_cursor()
	logic.report_to(GameSession, species_id, forlorn)
	_save()
	GameSession.encyclopaedia_fragments_formed.connect(_on_fragments_formed)
	_body.resized.connect(_layout)
	_layout()
	if logic.desk.ids().is_empty():
		_say("UI_ASSEMBLY_NOTICE_EMPTY")


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = COLOR_BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 28)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 24)
	column.add_child(header)
	var title := Label.new()
	title.text = tr("UI_ASSEMBLY_TITLE")
	title.add_theme_font_size_override("font_size", 26)
	header.add_child(title)
	var name_label := Label.new()
	var species: SpeciesData = GameData.species(species_id)
	name_label.text = tr(species.name_key()) if species != null else ""
	name_label.add_theme_font_size_override("font_size", 26)
	name_label.add_theme_color_override("font_color", COLOR_GOLD)
	header.add_child(name_label)
	_summary = Label.new()
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_summary.add_theme_font_size_override("font_size", 16)
	_summary.add_theme_color_override("font_color", COLOR_DIM)
	header.add_child(_summary)

	_body = Control.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_body)
	_stage = Control.new()
	_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.draw.connect(_draw_stage)
	_body.add_child(_stage)
	_layer = Control.new()
	_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(_layer)
	_new_label = Label.new()
	_new_label.text = tr("UI_ASSEMBLY_NEW_AREA")
	_new_label.add_theme_font_size_override("font_size", 14)
	_new_label.add_theme_color_override("font_color", COLOR_NEW_EDGE)
	_body.add_child(_new_label)
	_notice = Label.new()
	_notice.add_theme_font_size_override("font_size", 18)
	_notice.add_theme_color_override("font_color", COLOR_GOLD)
	_notice.add_theme_color_override("font_outline_color", Color.BLACK)
	_notice.add_theme_constant_override("outline_size", 6)
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.modulate.a = 0.0
	_body.add_child(_notice)

	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 13)
	_hint.add_theme_color_override("font_color", Color(0.55, 0.58, 0.65))
	column.add_child(_hint)


# --------------------------------------------------------------------------
# Layout and drawing
# --------------------------------------------------------------------------


func _layout() -> void:
	var b := _body.size
	if b.x < 100.0 or b.y < 100.0 or logic == null:
		return
	_desk_area = Rect2(0.0, 0.0, b.x - NEW_AREA_WIDTH - AREA_GAP, b.y)
	_new_area = Rect2(b.x - NEW_AREA_WIDTH, 0.0, NEW_AREA_WIDTH, b.y)
	_desk_rect = Logic.desk_rect(_desk_area.grow(-8.0))
	_tile_px = Logic.tile_px_for(_desk_rect.size)
	_new_inner = Rect2(
		_new_area.position + Vector2(12.0, 36.0), _new_area.size - Vector2(24.0, 48.0)
	)
	_new_label.position = _new_area.position + Vector2(14.0, 10.0)
	_notice.position = Vector2(_desk_area.position.x, _desk_area.end.y - 40.0)
	_notice.size = Vector2(_desk_area.size.x, 30.0)
	_stage.queue_redraw()
	refresh(false)


func _draw_stage() -> void:
	_stage.draw_rect(_desk_area, COLOR_DESK)
	_stage.draw_rect(_desk_area, COLOR_DESK_EDGE, false, 2.0)
	if _grid_alpha > 0.01:
		var colour := Color(COLOR_GRID.r, COLOR_GRID.g, COLOR_GRID.b, 0.2 * _grid_alpha)
		var strong := Color(COLOR_GRID.r, COLOR_GRID.g, COLOR_GRID.b, 0.4 * _grid_alpha)
		var top := _desk_rect.position.y
		var bottom := _desk_rect.end.y
		for x in range(Logic.DESK_TILES.x + 1):
			var at := _desk_rect.position.x + x * _tile_px
			_stage.draw_line(
				Vector2(at, top), Vector2(at, bottom), strong if x % 4 == 0 else colour
			)
		for y in range(Logic.DESK_TILES.y + 1):
			var at := top + y * _tile_px
			var left := _desk_rect.position.x
			var right := _desk_rect.end.x
			_stage.draw_line(
				Vector2(left, at), Vector2(right, at), strong if y % 4 == 0 else colour
			)
		_stage.draw_rect(_desk_rect, strong, false, 2.0)
	# The new fragment area: another colour, a double border, one of them dashed; no grid.
	_stage.draw_rect(_new_area, COLOR_NEW)
	_stage.draw_rect(_new_area, COLOR_NEW_EDGE, false, 3.0)
	var inner := _new_area.grow(-7.0)
	var dashed := Color(COLOR_NEW_EDGE.r, COLOR_NEW_EDGE.g, COLOR_NEW_EDGE.b, 0.7)
	_stage.draw_dashed_line(
		inner.position, Vector2(inner.end.x, inner.position.y), dashed, 1.5, 7.0
	)
	_stage.draw_dashed_line(Vector2(inner.end.x, inner.position.y), inner.end, dashed, 1.5, 7.0)
	_stage.draw_dashed_line(inner.end, Vector2(inner.position.x, inner.end.y), dashed, 1.5, 7.0)
	_stage.draw_dashed_line(
		Vector2(inner.position.x, inner.end.y), inner.position, dashed, 1.5, 7.0
	)


func _set_grid_alpha(value: float) -> void:
	_grid_alpha = value
	_stage.queue_redraw()


## Fades the grid in or out. `instant` skips the fade.
func _show_grid(on: bool, instant: bool = false) -> void:
	var target := 1.0 if on else 0.0
	if _grid_tween != null:
		_grid_tween.kill()
	if instant:
		_set_grid_alpha(target)
		return
	_grid_tween = create_tween()
	_grid_tween.tween_method(_set_grid_alpha, _grid_alpha, target, 0.14)


# --------------------------------------------------------------------------
# Keeping the views in step with the desk
# --------------------------------------------------------------------------


## Puts every fragment's drawing where the desk says it is, and redresses everything. With
## `animate` the drawings glide, and those of removed fragments vanish; `kicks` (id to a
## pixel offset) makes the drawings of those fragments overshoot, as when pushed back.
func refresh(animate: bool = false, kicks: Dictionary = {}) -> void:
	if logic == null or _tile_px <= 0.0:
		return
	var order: Array = logic.new_area_order()
	var layout := Logic.slot_layout(_new_inner.size, order.size(), minf(_tile_px * 4.0, 96.0))
	for id in logic.desk.ids():
		var fresh := not _views.has(id)
		if fresh:
			_views[id] = _make_view(id)
		var view: FragmentView = _views[id]
		var f: Fragment = logic.desk.fragment(id)
		var to := Vector2.ZERO
		var side := 0.0
		if f.area == Fragment.Area.DESK:
			to = Logic.tile_to_px(f.position, _tile_px, _desk_rect.position)
			side = _tile_px * Logic.FRAGMENT_TILES
		else:
			to = Logic.slot_position(order.find(id), layout, _new_inner)
			side = layout["slot"]
		var turns: int = view.turns + posmod(f.rotation - view.turns + 2, 4) - 2
		var seconds := GLIDE_SECONDS if animate and not fresh else 0.0
		view.glide(to, side, turns, seconds, kicks.get(id, Vector2.ZERO))
	for id in _views.keys():
		if not logic.desk.has_fragment(id):
			var gone: FragmentView = _views[id]
			_views.erase(id)
			if animate:
				gone.vanish()
			else:
				gone.queue_free()
	_dress()
	_show_grid(logic.grid_visible(), not animate)


func _make_view(id: Variant) -> FragmentView:
	var view := FragmentView.new()
	var f: Fragment = logic.desk.fragment(id)
	view.id = id
	view.edges = f.edges
	if f.is_parasitic():
		view.texture = _decoy
		view.art_cell = Art.decoy_cell(int(id))
	else:
		view.texture = _picture
		view.art_cell = f.page_cell
	_layer.add_child(view)
	return view


## Marks, damage, stains and the texts that follow from the desk's state.
func _dress() -> void:
	var held_group := []
	if logic.selected != null:
		held_group = logic.desk.group_of(logic.selected)
	for id in _views:
		var view: FragmentView = _views[id]
		var f: Fragment = logic.desk.fragment(id)
		var mark := FragmentView.Mark.NONE
		if held_group.has(id):
			mark = FragmentView.Mark.SELECTED
		elif logic.cursor == id and logic.selected == null:
			mark = FragmentView.Mark.CURSOR
		view.dress(f.damaged, f.stain, logic.desk.group_of(id).size() > 1, mark)
		view.z_index = 5 if held_group.has(id) else (1 if logic.cursor == id else 0)
	var arranged: int = logic.desk.arranged_count()
	_summary.text = tr("UI_ASSEMBLY_SUMMARY") % [arranged, Logic.PAGE_FRAGMENTS, _percent()]
	_hint.text = tr("UI_ASSEMBLY_HINT_HOLD" if logic.is_selected() else "UI_ASSEMBLY_HINT_BROWSE")


func _percent() -> int:
	return GameSession.page_ifp(species_id, forlorn)


## The pixel centre of every fragment's drawing, for the cursor to hop by.
func _centres() -> Dictionary:
	var centres := {}
	for id in _views:
		var view: FragmentView = _views[id]
		var f: Fragment = logic.desk.fragment(id)
		var side := _tile_px * Logic.FRAGMENT_TILES
		if f.area == Fragment.Area.DESK:
			centres[id] = (
				Logic.tile_to_px(f.position, _tile_px, _desk_rect.position)
				+ Vector2(side, side) / 2.0
			)
		else:
			centres[id] = view.position + view.size / 2.0
	return centres


# --------------------------------------------------------------------------
# Input
# --------------------------------------------------------------------------


func _unhandled_input(event: InputEvent) -> void:
	if logic == null:
		return
	if event.is_action_pressed("ui_cancel"):
		if logic.is_selected():
			_put_down()
		else:
			_close()
	elif event.is_action_pressed("ui_accept"):
		if logic.is_selected():
			_put_down()
		else:
			_pick_up()
	elif _direction_event(event) != Vector2i.ZERO:
		_held = _direction_event(event)
		_hold_time = 0.0
		_next_fire = REPEAT_DELAY
		_act_on(_held)
	elif event.is_action_pressed("assembly_rotate_left"):
		_turn(false)
	elif event.is_action_pressed("assembly_rotate_right"):
		_turn(true)
	elif event.is_action_pressed("assembly_stash"):
		_stash()
	elif event.is_action_pressed("ui_focus_next"):
		_cycle(1)
	elif event.is_action_pressed("ui_focus_prev"):
		_cycle(-1)
	else:
		return
	get_viewport().set_input_as_handled()


func _direction_event(event: InputEvent) -> Vector2i:
	for action in _direction_actions():
		if event.is_action_pressed(action):
			return _direction_actions()[action]
	return Vector2i.ZERO


func _direction_actions() -> Dictionary:
	return {
		"ui_left": Vector2i.LEFT,
		"ui_right": Vector2i.RIGHT,
		"ui_up": Vector2i.UP,
		"ui_down": Vector2i.DOWN,
	}


func _process(delta: float) -> void:
	if logic == null:
		return
	if _held != Vector2i.ZERO:
		var still_down := false
		for action in _direction_actions():
			if _direction_actions()[action] == _held and Input.is_action_pressed(action):
				still_down = true
		if not still_down:
			_held = Vector2i.ZERO
		else:
			_hold_time += delta
			while _hold_time >= _next_fire:
				_next_fire += REPEAT_INTERVAL
				_act_on(_held)
	if logic.is_selected():
		var turning := Input.is_action_pressed("assembly_rotate_left")
		turning = turning or Input.is_action_pressed("assembly_rotate_right")
		if _held != Vector2i.ZERO or turning or _handling_left > 0.0:
			_handling_left -= delta
			logic.handle(delta)
			_dress()


## An arrow: the held fragment moves, or the cursor hops.
func _act_on(direction: Vector2i) -> void:
	if logic.is_selected():
		_request(logic.step(direction), direction)
	else:
		logic.hop_cursor(_centres(), Vector2(direction))
		_dress()


func _turn(clockwise: bool) -> void:
	if logic.is_selected():
		_request(logic.turn(clockwise), Vector2i.ZERO)


func _stash() -> void:
	if logic.is_selected():
		var group_size: int = logic.desk.group_of(logic.selected).size()
		if group_size == 1 and logic.stash():
			_save()
			refresh(true)
		else:
			_shake_held(Vector2.RIGHT)


func _cycle(step: int) -> void:
	if not logic.is_selected():
		logic.cycle_cursor(step)
		_dress()


func _pick_up() -> void:
	if logic.select(logic.cursor):
		refresh(true)


func _put_down() -> void:
	logic.release()
	_held = Vector2i.ZERO
	_save()
	refresh(true)


func _close() -> void:
	logic.release()
	_save()
	closed.emit()
	if get_tree().current_scene == self:
		TransitionManager.change_scene(RETURN_SCENE)


# --------------------------------------------------------------------------
# What a request did
# --------------------------------------------------------------------------


func _request(outcome: Variant, direction: Vector2i) -> void:
	if outcome.desk_full:
		_say("UI_ASSEMBLY_NOTICE_FULL")
		_shake_held(Vector2.RIGHT)
		return
	if not outcome.accepted():
		sound_requested.emit(&"refused")
		var axis := Vector2(direction) if direction != Vector2i.ZERO else Vector2.RIGHT
		_shake_held(axis)
		return
	_handling_left = GLIDE_SECONDS
	var kicks := {}
	var snap: Results.SnapResult = outcome.snap
	if (
		outcome.pushed_back()
		and logic.desk.has_fragment(snap.a)
		and logic.desk.has_fragment(snap.b)
	):
		var toward: Vector2 = _centre_of(snap.b) - _centre_of(snap.a)
		for id in logic.desk.group_of(snap.mover):
			kicks[id] = toward.normalized() * _tile_px * 0.7
	refresh(true, kicks)
	_show(outcome)
	logic.report_to(GameSession, species_id, forlorn, outcome)
	_save()
	_dress()


func _show(outcome: Variant) -> void:
	var snap: Results.SnapResult = outcome.snap
	if snap == null:
		return
	if snap.reason == Results.SnapResult.Reason.OK:
		sound_requested.emit(&"snap")
		for id in logic.desk.group_of(snap.a):
			_pulse(id, COLOR_GOLD)
	else:
		for id in snap.damaged:
			_pulse(id, Color(1.0, 0.25, 0.2))
	if outcome.parasites_removed.size() > 0:
		sound_requested.emit(&"parasite_snicker")
	if outcome.is_hole():
		_say("UI_ASSEMBLY_NOTICE_HOLE")
	if outcome.destroyed.size() > 0:
		_say("UI_ASSEMBLY_NOTICE_DESTROYED")
	if outcome.completed:
		sound_requested.emit(&"page_assembled")
		_say("UI_ASSEMBLY_NOTICE_COMPLETE")
		for id in _views:
			_pulse(id, COLOR_GOLD)


func _pulse(id: Variant, colour: Color) -> void:
	if _views.has(id):
		(_views[id] as FragmentView).pulse(colour)


func _shake_held(axis: Vector2) -> void:
	if logic.selected == null:
		return
	for id in logic.desk.group_of(logic.selected):
		var view: FragmentView = _views[id]
		var at := view.position
		view.flash_colour = Color(1.0, 0.3, 0.25)
		view.shake(at, axis, _tile_px * 0.35)


func _centre_of(id: Variant) -> Vector2:
	var f: Fragment = logic.desk.fragment(id)
	var side := _tile_px * Logic.FRAGMENT_TILES
	return Logic.tile_to_px(f.position, _tile_px, _desk_rect.position) + Vector2(side, side) / 2.0


## Shows a notice for a few seconds.
func _say(key: String) -> void:
	_notice.text = tr(key)
	_notice.modulate.a = 1.0
	if _notice_tween != null:
		_notice_tween.kill()
	_notice_tween = create_tween()
	_notice_tween.tween_interval(NOTICE_SECONDS)
	_notice_tween.tween_property(_notice, "modulate:a", 0.0, 0.6)


func _save() -> void:
	GameSession.set_puzzle_state(species_id, forlorn, logic.save_state())


func _on_fragments_formed(formed_species: StringName, formed_forlorn: bool, _count: int) -> void:
	if formed_species != species_id or formed_forlorn != forlorn or logic == null:
		return
	logic.add_new_fragments(
		GameSession.true_fragments(species_id, forlorn),
		GameSession.parasitic_fragments(species_id, forlorn)
	)
	_save()
	refresh(true)
