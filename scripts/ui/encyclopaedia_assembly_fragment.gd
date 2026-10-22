## One fragment on the assembly screen: a square piece of a procedural picture with an outline
## shaped by its sides, a black stain growing from its centre, and cracks once it is damaged.
##
## It holds no rules: the screen tells it what to look like, and moves it with [method glide].
## It is drawn upright (as on the page); a quarter turn is the node's own `rotation`.
##
## No `class_name` (the CLI class-cache trap): the screen preloads this.
extends Control

const Art := preload("res://scripts/ui/encyclopaedia_assembly_art.gd")
const Logic := preload("res://scripts/ui/encyclopaedia_assembly_logic.gd")

enum Mark { NONE, CURSOR, SELECTED }

const OUTLINE := Color(0.82, 0.86, 0.95, 0.9)
const OUTLINE_ARRANGED := Color(0.95, 0.82, 0.42, 1.0)
const OUTLINE_DAMAGED := Color(0.75, 0.25, 0.2, 1.0)
const DAMAGED_TINT := Color(0.78, 0.55, 0.5)
const CURSOR_COLOUR := Color(0.45, 0.85, 1.0)
const SELECTED_COLOUR := Color(1.0, 1.0, 1.0)

var id: Variant
var edges := PackedInt32Array([0, 0, 0, 0])
var texture: Texture2D
## The cell of the picture this fragment shows.
var art_cell := Vector2i.ZERO
var damaged: bool = false
## How much of the fragment the stain covers, 0 to the balance's cap.
var stain: float = 0.0
## Stuck to another fragment.
var arranged: bool = false
var mark: Mark = Mark.NONE
## 0..1: a flash of colour (`flash_colour`) over the fragment, fading out.
var flash: float = 0.0
var flash_colour := Color(1.0, 0.3, 0.25)
## Quarter turns the node was turned by in all, unwrapped: -1 and 3 are the same turn, but the
## animation must go the short way.
var turns: int = 0

var _tween: Tween


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		pivot_offset = size / 2.0
		queue_redraw()


func set_flash(value: float) -> void:
	flash = value
	queue_redraw()


## Fades `flash` out from 1, in `colour`.
func pulse(colour: Color, seconds: float = 0.5) -> void:
	flash_colour = colour
	flash = 1.0
	var tween := create_tween()
	tween.tween_method(set_flash, 1.0, 0.0, seconds)


## Sets what the fragment looks like, redrawing only if that changed.
func dress(is_damaged: bool, dirt: float, is_arranged: bool, new_mark: Mark) -> void:
	if (
		is_damaged != damaged
		or not is_equal_approx(dirt, stain)
		or is_arranged != arranged
		or new_mark != mark
	):
		damaged = is_damaged
		stain = dirt
		arranged = is_arranged
		mark = new_mark
		queue_redraw()


## Puts the fragment at `to` (top-left, in its parent's pixels), `to_size` wide and `to_turns`
## quarter turns, gliding there. A `kick` makes it overshoot by that much first, as when
## something pushes it back. Without `seconds` it simply is there.
func glide(
	to: Vector2, to_size: float, to_turns: int, seconds: float = 0.0, kick: Vector2 = Vector2.ZERO
) -> void:
	if _tween != null:
		_tween.kill()
	turns = to_turns
	var angle := to_turns * PI / 2.0
	if seconds <= 0.0:
		position = to
		size = Vector2(to_size, to_size)
		rotation = angle
		return
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.set_trans(Tween.TRANS_QUAD)
	_tween.set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "size", Vector2(to_size, to_size), seconds)
	_tween.tween_property(self, "rotation", angle, seconds)
	if kick == Vector2.ZERO:
		_tween.tween_property(self, "position", to, seconds)
	else:
		_tween.tween_property(self, "position", to + kick, seconds * 0.4)
		_tween.chain().tween_property(self, "position", to, seconds * 1.2)


## A short shake along `axis`, ending where the fragment already should be: `at`.
func shake(at: Vector2, axis: Vector2, strength: float) -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_SINE)
	for factor in [1.0, -0.8, 0.5, -0.25, 0.0]:
		_tween.tween_property(self, "position", at + axis * strength * factor, 0.05)
	pulse(flash_colour, 0.3)


## Vanishes: shrinks and fades, then frees itself.
func vanish(seconds: float = 0.4) -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(self, "scale", Vector2(0.2, 0.2), seconds)
	_tween.tween_property(self, "modulate:a", 0.0, seconds)
	_tween.chain().tween_callback(queue_free)


func _draw() -> void:
	var side := size.x
	if side <= 1.0 or texture == null:
		return
	var points := Art.outline(edges, side)
	var uvs := PackedVector2Array()
	var cols := float(Logic.PAGE_COLS)
	var rows := float(Logic.PAGE_ROWS)
	for p in points:
		uvs.append(Vector2((art_cell.x + p.x / side) / cols, (art_cell.y + p.y / side) / rows))
	var tint := DAMAGED_TINT if damaged else Color.WHITE
	var colours := PackedColorArray()
	colours.resize(points.size())
	colours.fill(tint)
	draw_polygon(points, colours, uvs, texture)
	# The stain, from the centre outwards, never quite to the edges.
	if stain > 0.01:
		var blob := Art.stain_blob(hash(id), stain * side * 0.5)
		draw_set_transform(size / 2.0)
		draw_colored_polygon(blob, Color(0.02, 0.0, 0.03, 0.94))
		draw_set_transform(Vector2.ZERO)
	if damaged:
		for line in Art.cracks(hash(id), side):
			draw_polyline(line, Color(0.08, 0.02, 0.02, 0.95), maxf(side * 0.025, 1.5), true)
	var closed := points + PackedVector2Array([points[0]])
	var line_colour := OUTLINE
	if damaged:
		line_colour = OUTLINE_DAMAGED
	elif arranged:
		line_colour = OUTLINE_ARRANGED
	draw_polyline(closed, line_colour, maxf(side * 0.03, 1.5), true)
	if flash > 0.0:
		var glow := Color(flash_colour.r, flash_colour.g, flash_colour.b, 0.55 * flash)
		draw_colored_polygon(points, glow)
	match mark:
		Mark.SELECTED:
			draw_polyline(closed, SELECTED_COLOUR, maxf(side * 0.07, 3.0), true)
		Mark.CURSOR:
			draw_polyline(closed, CURSOR_COLOUR, maxf(side * 0.05, 2.5), true)
