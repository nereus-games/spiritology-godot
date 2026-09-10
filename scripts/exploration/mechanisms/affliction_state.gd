## The affliction state carried by an exploration actor, player or rival.
##
## Gathers the lingering effects the traps inflict (the design doc's "Mechanisms / Traps"):
## poison, which costs DEN per turn, and disarray, which deflects moves. Effects STACK — within
## one type, only the duration adds up.
##
## No `class_name`: only the editor regenerates the global class cache, and this game is launched
## from the command line. The actors reference this script by `preload`.
extends RefCounted

## How likely a move is to be deflected while under disarray. The design doc says 35%.
const DISARRAY_DEVIATION_CHANCE := 0.35

# Poison: turns left, and DEN taken each turn.
var poison_turns := 0
var poison_per_turn := 0

# Disarray: the queue of upcoming moves, each deflected (true) or not (false). Built when the
# disarray is added, per the rule: out of N moves (3-5), 2 have a 35% chance of being deflected
# and the other N-2 certainly are; the order is then shuffled, so that no run comes out with
# zero deflections and reads as broken.
var _disarray_queue: Array[bool] = []

var _rng := RandomNumberGenerator.new()


## `seed_value >= 0` makes the disarray deflection deterministic, for tests.
func _init(seed_value := -1) -> void:
	if seed_value >= 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()


## Adds poison. Stacking: the duration adds up, the magnitude takes the stronger of the two —
## the design doc says "only the duration is augmented".
func add_poison(turns: int, per_turn: int) -> void:
	poison_turns += maxi(turns, 0)
	poison_per_turn = maxi(poison_per_turn, maxi(per_turn, 0))


## Adds a burst of disarray lasting `moves` moves, stacking with any in progress. The rule: 2
## moves at 35%, the other `moves - 2` deflected for certain, in shuffled order.
func add_disarray(moves: int) -> void:
	var n := maxi(moves, 0)
	if n <= 0:
		return
	var forced := maxi(n - 2, 0)
	var seg: Array[bool] = []
	for i in range(forced):
		seg.append(true)
	for i in range(n - forced):  # the remaining 2, or fewer, at 35%
		seg.append(_rng.randf() < DISARRAY_DEVIATION_CHANCE)
	# Fisher-Yates with the internal rng, so the order is random but deterministic under test.
	for i in range(seg.size() - 1, 0, -1):
		var j := _rng.randi() % (i + 1)
		var tmp := seg[i]
		seg[i] = seg[j]
		seg[j] = tmp
	_disarray_queue.append_array(seg)


func has_poison() -> bool:
	return poison_turns > 0


func has_disarray() -> bool:
	return not _disarray_queue.is_empty()


## Disarray moves left, for the HUD.
func remaining_disarray() -> int:
	return _disarray_queue.size()


func is_afflicted() -> bool:
	return has_poison() or has_disarray()


## Elapses one turn of poison. Returns the DEN to take this turn, 0 when not poisoned.
func tick_poison() -> int:
	if poison_turns <= 0:
		return 0
	poison_turns -= 1
	return poison_per_turn


## Looks at the next move WITHOUT consuming it: `true` if it would be deflected. Needed by free
## look, where the deflection applies to the gesture but the count only moves when that gesture
## actually commits a turn (see [code]PlayerInputHandler._disarrayed_mouse[/code]) — a trap you
## could drain by waggling the mouse without ever spending a turn would be no trap at all.
func peek_move() -> bool:
	return _disarray_queue[0] if not _disarray_queue.is_empty() else false


## Consumes the next move from the disarray queue. Returns `true` when THAT move must be
## deflected. With no disarray left it always returns `false`.
##
## What counts as ONE move (per the design doc, with no free-look exception since 2026-09-02): a
## step, a keyboard turn, a turn COMMITTED through free look, and each tile crossed on a narrow
## bridge — where the deflection itself does not apply, for want of another direction to go. A
## mouse gesture that commits no turn is deflected without counting anything down (see
## [method peek_move]).
##
## TODO (encounter): the design doc has disarray still active when an encounter opens carry into
## it — "each player action count as a movement and has 35% or 100% chance of being a different
## one than chosen". NOTHING is wired: the `scripts/encounter/` layer knows nothing of
## afflictions, for players or rivals (the same missing wiring as handing a rival's poison to the
## encounter). To be taken up when exploration and encounter are better connected; it first needs
## deciding what "a different one" means in the encounter menu — a different ability, a different
## target, or both.
func consume_move() -> bool:
	if _disarray_queue.is_empty():
		return false
	return _disarray_queue.pop_front()


## Cures poison outright (the Tea drop object, [enum GameEnums.ObjectEffect] CURE_POISON).
func cure_poison() -> void:
	poison_turns = 0
	poison_per_turn = 0
