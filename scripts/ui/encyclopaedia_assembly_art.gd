## Procedural pictures for the assembly desk: what a fragment looks like, drawn from its sides.
##
## PLACEHOLDER art, in the sense that matters: nothing here is an asset, and nothing is text. A
## page is a picture of 3 x 11 cells, drawn from a seed, and a fragment shows its own cell of it,
## so that neighbouring fragments continue each other. A parasitic fragment shows a cell of
## ANOTHER picture, drawn from the same seed with other phases: it looks like a fragment and does
## not continue anything, which is all a parasite should give away.
##
## A fragment's outline follows its four sides, a 6-bit profile each (puzzle_edges.gd): a set bit
## is a tab, a clear bit a notch, so that two sides that fit, being negatives of each other, mesh.
##
## No `class_name` (the CLI class-cache trap): referenced by `preload`.
extends RefCounted

const Logic := preload("res://scripts/ui/encyclopaedia_assembly_logic.gd")
const Edges := preload("res://scripts/encyclopaedia/puzzle_edges.gd")

## Pixels a cell of a picture is drawn with.
const CELL_PX := 48
## How far a tab sticks out of, and a notch goes into, a fragment: a fraction of its side.
const TAB_DEPTH := 0.075
## Share of a side, at each end, that stays straight.
const CORNER_FLAT := 0.09
## Points per side of a smoothly drawn profile.
const PROFILE_STEPS := 4

static var _pictures := {}


## The picture of a page, or the decoy that parasitic fragments show.
static func picture(page_seed: int, decoy: bool) -> Texture2D:
	var key := "%d/%s" % [page_seed, decoy]
	if _pictures.has(key):
		return _pictures[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = page_seed + (7919 if decoy else 0)
	var phase_a := rng.randf() * TAU
	var phase_b := rng.randf() * TAU
	var phase_c := rng.randf() * TAU
	var hue_shift := rng.randf()
	var centre := Vector2(0.9 + rng.randf() * 1.2, 3.0 + rng.randf() * 5.0)
	var width := Logic.PAGE_COLS * CELL_PX
	var height := Logic.PAGE_ROWS * CELL_PX
	var image := Image.create_empty(width, height, false, Image.FORMAT_RGB8)
	for y in height:
		for x in width:
			var u := float(x) / CELL_PX
			var v := float(y) / CELL_PX
			var rings := 0.5 + 0.5 * sin((Vector2(u, v) - centre).length() * 3.3 + phase_a)
			var streaks := 0.5 + 0.5 * sin((u * 1.9 + v * 0.8) * 2.6 + phase_b)
			var swirl := 0.5 + 0.5 * sin(u * 2.1 - v * 1.3 + phase_c + rings * 2.0)
			var hue := fposmod(hue_shift + 0.10 * rings + 0.18 * swirl + v * 0.012, 1.0)
			var shade := 0.42 + 0.30 * streaks + 0.20 * rings
			image.set_pixel(x, y, Color.from_hsv(hue, 0.40 + 0.35 * swirl, clampf(shade, 0.0, 1.0)))
	var texture := ImageTexture.create_from_image(image)
	_pictures[key] = texture
	return texture


## The cell of the decoy picture a parasitic fragment shows, from its id.
static func decoy_cell(id: int) -> Vector2i:
	var h := absi(hash([id, 31337]))
	return Vector2i(h % Logic.PAGE_COLS, (h / 7) % Logic.PAGE_ROWS)


## The outline of a fragment `size` pixels square, from its four sides as drawn on the page
## (rotation 0), clockwise from the top-left corner. Tabs go out of the square, notches into it.
static func outline(edges: PackedInt32Array, size: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var depth := size * TAB_DEPTH
	for side in [Edges.NORTH, Edges.EAST, Edges.SOUTH, Edges.WEST]:
		# A south or west side is read against the way the outline walks it.
		var walked_backwards: bool = side == Edges.SOUTH or side == Edges.WEST
		var profile := _profile(edges[side])
		if walked_backwards:
			profile.reverse()
		# The last point of a side is the first of the next one.
		for i in profile.size() - 1:
			points.append(_place(side, profile[i].x, profile[i].y, size, depth))
	return points


## One side's profile as (t along the side, o across it: 1 a tab, -1 a notch) points, read in
## the canonical direction: straight at both ends, in between a trapezoid per bit.
static func _profile(signature: int) -> Array[Vector2]:
	var run: Array[Vector2] = [Vector2(0.0, 0.0)]
	var width := (1.0 - 2.0 * CORNER_FLAT) / Edges.BITS
	for bit in Edges.BITS:
		var value := 1.0 if (signature & (1 << bit)) != 0 else -1.0
		var start := CORNER_FLAT + bit * width
		run.append(Vector2(start + width * 0.15, value))
		run.append(Vector2(start + width * 0.85, value))
	run.append(Vector2(1.0, 0.0))
	return run


## Where a profile point lies on `side` of a square of `size`.
static func _place(side: int, t: float, o: float, size: float, depth: float) -> Vector2:
	match side:
		Edges.NORTH:
			return Vector2(t * size, -o * depth)
		Edges.EAST:
			return Vector2(size + o * depth, t * size)
		Edges.SOUTH:
			return Vector2(t * size, size + o * depth)
		_:
			return Vector2(-o * depth, t * size)


## The black stain's outline, a ragged disc of radius `radius` about the origin, from the id.
static func stain_blob(id: int, radius: float) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([id, 4242])
	var points := PackedVector2Array()
	var count := 28
	var phase := rng.randf() * TAU
	var wobble := rng.randf_range(0.05, 0.1)
	for i in count:
		var angle := TAU * i / count
		var r := radius * (1.0 + wobble * sin(angle * 3.0 + phase) + rng.randf_range(-0.03, 0.03))
		points.append(Vector2(cos(angle), sin(angle)) * r)
	return points


## The cracks of a damaged fragment: a few jagged lines running in from the edges.
static func cracks(id: int, size: float) -> Array[PackedVector2Array]:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([id, 9001])
	var lines: Array[PackedVector2Array] = []
	for _i in 3:
		var side := rng.randi_range(0, 3)
		var along := rng.randf_range(0.2, 0.8) * size
		var start := (
			[Vector2(along, 0.0), Vector2(size, along), Vector2(along, size), Vector2(0.0, along)][side]
			as Vector2
		)
		var inward := (Vector2(size, size) / 2.0 - start).normalized()
		var line := PackedVector2Array([start])
		var here := start
		for _j in 5:
			var jitter := Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * 0.55
			here += (inward + jitter).normalized() * size * rng.randf_range(0.08, 0.16)
			line.append(here)
		lines.append(line)
	return lines
