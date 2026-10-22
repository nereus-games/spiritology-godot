## The shape of a fragment's sides, and what makes two sides complementary.
##
## The doc asks for sides of "irregular but complementary shape". Here a side is a small bit
## pattern, its profile read along the side, and two sides fit when one is the exact negative of
## the other: every bit set on one is clear on the other. That is enough to make sides irregular
## (62 usable patterns per side), to make a fit checkable by one XOR, and to keep it
## deterministic: the same seed draws the same sides.
##
## A fragment keeps its four sides as drawn on the PAGE (rotation 0), in the order NORTH, EAST,
## SOUTH, WEST. A side is always read in the same physical direction, west to east on a north or
## south side and north to south on an east or west side; `side_signature` does the bookkeeping
## when a fragment is rotated.
extends RefCounted

const NORTH := 0
const EAST := 1
const SOUTH := 2
const WEST := 3

## Bits in a side's profile.
const BITS := 6
## All profile bits set. A profile of 0 or FULL would be a flat side, which fits nothing.
const FULL := (1 << BITS) - 1

## Unit step of each side, in grid coordinates (y points down).
const STEP: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]


## The side facing `side`.
static func opposite(side: int) -> int:
	return (side + 2) % 4


## The profile that fits `signature`.
static func complement(signature: int) -> int:
	return signature ^ FULL


## Whether two sides, read in the same direction, fit each other.
static func compatible(a: int, b: int) -> bool:
	return (a ^ b) == FULL


## One irregular, non-flat profile.
static func random_signature(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(1, FULL - 1)


## Four independent random sides, for a fragment that belongs to no page (a parasite).
static func random_edges(rng: RandomNumberGenerator) -> PackedInt32Array:
	var edges := PackedInt32Array()
	for _i in 4:
		edges.append(random_signature(rng))
	return edges


## The sides of every fragment of a `cols` x `rows` page, as {Vector2i cell: PackedInt32Array}.
## Two neighbouring cells are given complementary sides along their shared border; the page's
## outer border gets random sides.
static func generate(cols: int, rows: int, rng: RandomNumberGenerator) -> Dictionary:
	var edges := {}
	for y in rows:
		for x in cols:
			edges[Vector2i(x, y)] = PackedInt32Array([0, 0, 0, 0])
	for y in rows:
		for x in cols:
			var cell := Vector2i(x, y)
			for side in [NORTH, EAST, SOUTH, WEST]:
				var neighbour: Vector2i = cell + STEP[side]
				if edges.has(neighbour) and edges[neighbour][opposite(side)] != 0:
					edges[cell][side] = complement(edges[neighbour][opposite(side)])
				else:
					edges[cell][side] = random_signature(rng)
	return edges


## The profile that a fragment with sides `edges`, turned `rotation` quarter-turns clockwise,
## presents on the physical side `side`, read in the canonical direction.
static func side_signature(edges: PackedInt32Array, rotation: int, side: int) -> int:
	var base := posmod(side - rotation, 4)
	var signature := edges[base]
	# A north or south side is read towards the east (1), an east or west one towards the
	# south (2). Turned clockwise, that direction turns with the fragment, and when it ends
	# up pointing north (0) or west (3) the profile is read backwards.
	var reading := EAST if base == NORTH or base == SOUTH else SOUTH
	var turned := (reading + rotation) % 4
	if turned == NORTH or turned == WEST:
		signature = _reverse(signature)
	return signature


static func _reverse(signature: int) -> int:
	var reversed := 0
	for i in BITS:
		if signature & (1 << i):
			reversed |= 1 << (BITS - 1 - i)
	return reversed
