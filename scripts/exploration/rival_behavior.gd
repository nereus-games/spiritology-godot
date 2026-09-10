## A rival on the dungeon grid, drawn as a billboard sprite. Acts on every player turn.
##
## Behaviour ported from the prototype onto the logical grid: chases the player while it is
## in sight, remembers its last known position for a few turns, and otherwise wanders. Moving
## onto the player's cell (or the other way round) starts an encounter. Turns arrive through
## [method take_turn], called by the [DungeonManager].
class_name RivalBehavior
extends Node3D

const AfflictionState := preload("res://scripts/exploration/mechanisms/affliction_state.gd")

@export var species_id := &"ravbak"  ## species, used to build the encounter
@export var vision_range := 5  ## detection range, in cells (Manhattan)
@export var turns_between_actions := 1  ## 1 = acts every turn, 2 = every other turn
@export var memory_turns := 2  ## turns of memory after losing sight
@export var move_duration := 0.18
## The sprite's maximum footprint in metres: it fits in a square of this side. The design
## doc's "Visuals + Sounds" caps rival sprites at 90 cm x 90 cm. A cell is
## [constant DungeonManager.CELL_SIZE] (1 m), so 0.9 fills most of the cell without ever
## spilling into its neighbours, whatever the shape of the drawing.
@export var world_height := 0.9

## The rival's maximum DEN, SET BY LEVEL DESIGN dungeon by dungeon. The design doc's
## ballpark figures are in [constant GameSession.RIVAL_DEN_EARLY] / _MID / _LATE, but nothing
## requires sticking to them exactly — this is a per-dungeon knob.
@export var max_den := GameSession.RIVAL_DEN_EARLY

## Chance of falling PER narrow-bridge cell crossed. The design doc: "a simple probability to
## fall of 1 to 2% — exact percentage is generated along with the rival". 0 means roll one.
@export var bridge_fall_chance := 0.0

## Appetite for chasing through a fall when the fall costs NOTHING — the design doc's "a rival
## may decide to fall to pursue the player". The roll is repeated at every opportunity, but
## weighted by what the fall would cost: see [method fall_pursuit_chance]. Falls only; stairs
## and elevators are free, and taken without hesitation.
@export var pursue_fall_chance := 0.5

## Caution exponent: the higher it is, the more the rival balks as soon as the fall would eat
## a noticeable share of its density. 1 is a linear trade-off, 2 markedly more careful.
@export var fall_prudence := 2.0

## How many turns a rival keeps chasing the player after seeing it change floor. Longer than
## [member memory_turns], because reaching a staircase takes turns, whereas ordinary memory
## only has to avoid losing a fresh trail.
##
## TODO (2026-09-02): this value has NEVER been tried in game, and the expiry itself is absent
## from the design doc — deliberately, until it has been tested. Revisit it in the chase-tuning
## pass, then write it into "Rivals".
@export var level_pursuit_turns := 8

var cell: Vector3i
var _dungeon: DungeonManager
var _busy := false

## Current DEN ON THE MAP, never displayed. Falls eat into it, it carries over into the
## encounter that follows, and a rival down to 0 is dissolved where it stands, with no
## encounter at all.
var den := 0

## Cross-floor chase: the cell the player was seen arriving on, and the turns left to reach
## it.
var _level_target: Vector3i
var _level_pursuit := 0

## Lingering effects on the rival (poison, disarray), written by the traps. Poison has no DEN
## to bite on the map — DEN lives in the encounter — so it is only counted down here, to be
## picked up when an encounter opens once that wiring exists.
var affliction := AfflictionState.new()

var _has_target := false
var _target_cell: Vector3i
var _memory := 0
var _cooldown := 0


func _ready() -> void:
	_fit_sprite()
	den = max_den
	# "exact percentage is generated along with the rival": each rival gets its own sure-
	# footedness, rolled once and for all inside the design doc's range.
	if bridge_fall_chance <= 0.0:
		bridge_fall_chance = randf_range(0.01, 0.02)
	_dungeon = get_tree().get_first_node_in_group("dungeon") as DungeonManager
	if _dungeon == null:
		push_error("[RivalBehavior] no DungeonManager in the 'dungeon' group.")
		return
	cell = _dungeon.world_to_cell(global_position)
	global_position = _dungeon.cell_to_world(cell)
	_dungeon.register_rival(self)


## Fits the sprite inside a square of [member world_height], whatever the PNG's resolution AND
## aspect ratio.
##
## Necessary because the sources run from 800x800 to 2341x3500 px. With a `pixel_size` frozen
## in the scene, every species would come out at a different size — at 0.02 ravbak stood 16
## units tall and fliritus would stand 70. So `pixel_size` is derived from the height we want
## rather than inherited from the resolution.
##
## Do NOT switch `rival.tscn` back to FULL billboard (`billboard = 1`): a full billboard aligns
## with ALL of the camera's axes, roll included. During a balance test the camera rolls with
## the player's wobble — and every visible rival leaned along with it. Y-fixed mode
## (`billboard = 2`) only spins them around the vertical.
func _fit_sprite() -> void:
	var sprite := get_node_or_null("Sprite3D") as Sprite3D
	if sprite == null or sprite.texture == null:
		return
	var tex_height := sprite.texture.get_height()
	var tex_width := sprite.texture.get_width()
	if tex_height <= 0 or tex_width <= 0:
		return
	# Fit against the LARGER side: fitting on height alone would let a drawing wider than it is
	# tall (jézal, 2000 x 1898) spill out of the cell sideways.
	sprite.pixel_size = world_height / float(maxi(tex_width, tex_height))
	# The quad is centred on its origin, so raise it by half its REAL height to have it stand on
	# the cell's floor instead of half-buried in it (or floating above).
	sprite.position.y = tex_height * sprite.pixel_size * 0.5


## Played by the DungeonManager every turn, with the player's current cell.
func take_turn(player_cell: Vector3i) -> void:
	if _busy or _dungeon == null:
		return
	if _cooldown > 0:
		_cooldown -= 1
		return
	_cooldown = turns_between_actions - 1

	# Cross-floor chase. No cross-floor vision is needed: the rival SAW the player leave and
	# remembers where it went.
	var pursuing_level := _level_pursuit > 0
	if pursuing_level:
		_level_pursuit -= 1
		if cell.y == _level_target.y:
			pursuing_level = false  # same floor now: the ordinary chase takes over
			_level_pursuit = 0
			_target_cell = _level_target
			_has_target = true
			_memory = memory_turns
		elif await _pursue_level():
			return  # the turn's action is spent (a fall or a staircase)
	if not pursuing_level:
		_update_memory(player_cell)

	var delta := _chase_dir(_target_cell) if _has_target else _random_dir()
	# Disarray: a share of the rival's moves is deflected at random.
	if affliction.consume_move():
		delta = _random_dir()
	var next := cell + delta

	# A closed gateway stops the rival too — and contact through it.
	if _dungeon.is_edge_blocked(cell, next):
		return

	# Stairs ahead, approached along their axis: the rival takes them like the player does
	# (carried two cells further, plus a floor change). From the wrong side they block like a
	# wall.
	var stairs := _stairs_at(next)
	if stairs != null:
		if delta == stairs.face_dir:
			await _use_level_link(stairs)
		return

	# On a plank, meeting is not settled by contact: both fall, per the design doc.
	if _dungeon.is_narrow_bridge(next):
		if next == player_cell:
			_dungeon.request_bridge_collision(self, next)
			return
		var occupant := _dungeon.occupant_at(next)
		if occupant != null and occupant != self:
			_collide_with_rival(next, occupant)
			return
	elif next == player_cell:
		_dungeon.request_encounter(self, true)  # contact starts an encounter, with no move
		return

	if _dungeon.move_occupant(cell, next, self):
		await _step_to(next)
		if _dungeon == null:
			return  # dissolved in the meantime
		_dungeon.notify_entered(next, self)  # traps on the cell it reached
		# The rival's balance test: one plank crossed, one chance to fall. A simplified version
		# of the player's real-time test — the design doc calls for "a similar test [...] a
		# simple probability to fall".
		if _dungeon.is_narrow_bridge(cell) and randf() < bridge_fall_chance:
			fall_down(cell)


func _update_memory(player_cell: Vector3i) -> void:
	if _can_see(player_cell):
		_target_cell = player_cell
		_has_target = true
		_memory = memory_turns
	elif _memory > 0:
		_memory -= 1
	else:
		_has_target = false


## Naive sight: Manhattan range, with NO occlusion.
##
## ## TODO: the design doc is now explicit — "the line of sight is blocked by walls" (the
## characters are small, eyes at [constant DungeonManager.EYE_HEIGHT] = 60 cm). A rival
## therefore sees through walls today, which no longer matches. What it would take: walk the
## cells between rival and player and cut the line at the first opaque edge
## ([method DungeonManager.is_edge_opaque]) or non-walkable cell. Revisit with real dungeons,
## where occlusion actually matters.
func _can_see(player_cell: Vector3i) -> bool:
	# The player is hidden (fog mantel, torment veil, a costume): undetectable.
	if _dungeon != null and _dungeon.rivals_ignore_player():
		return false
	if player_cell.y != cell.y:
		return false
	var d: Vector3i = (player_cell - cell).abs()
	return d.x + d.z <= vision_range


func _chase_dir(target: Vector3i) -> Vector3i:
	var diff := target - cell
	if absi(diff.x) > absi(diff.z):
		return Vector3i(signi(diff.x), 0, 0)
	return Vector3i(0, 0, signi(diff.z))


func _random_dir() -> Vector3i:
	match randi() % 4:
		0:
			return Vector3i(1, 0, 0)
		1:
			return Vector3i(-1, 0, 0)
		2:
			return Vector3i(0, 0, 1)
		_:
			return Vector3i(0, 0, -1)


func _step_to(next: Vector3i) -> void:
	cell = next
	_busy = true
	var tween := create_tween()
	tween.tween_property(self, "global_position", _dungeon.cell_to_world(next), move_duration)
	await tween.finished
	_busy = false


## Instant relocation onto a cell (the teleport trap). Occupancy is handled by
## [method DungeonManager.teleport_actor].
func teleport_to(to_cell: Vector3i) -> void:
	cell = to_cell
	global_position = _dungeon.cell_to_world(to_cell)


# --------------------------------------------------------------------------
# Narrow bridges: falling, meeting, map DEN
# --------------------------------------------------------------------------


## The player has just changed floor in front of the rival — a fall, stairs, an elevator. The
## rival remembers WHERE it went and chases by its own means (see [method _pursue_level]). No
## cross-floor vision is needed: what is seen is the DEPARTURE.
func witness_player_level_change(from_cell: Vector3i, to_cell: Vector3i) -> void:
	if not _can_see(from_cell):
		return
	_level_target = to_cell
	_level_pursuit = level_pursuit_turns


## One turn of chasing towards the player's floor. Returns true when the turn's action is
## spent (the rival jumped or took stairs); false when it still has to move, in which case the
## target cell has been set to the staircase to reach.
##
## Two ways down, only one of them free: stairs are taken without hesitation, while throwing
## yourself off an edge costs DEN — hence the roll on [member pursue_fall_chance], which is
## what the design doc's "may decide" comes down to.
func _pursue_level() -> bool:
	var going_down: bool = _level_target.y < cell.y
	if going_down:
		# You cannot throw yourself off from just anywhere: it takes an open EDGE to step over. A
		# guardrail (or a closed gateway) on that edge holds the rival back exactly as it holds
		# the player back.
		var brink := _open_drop_edge(_level_target)
		if brink != cell:
			var landing: Vector3i = _dungeon.fall_landing(brink)
			# Only jump if it actually gets closer — do not overshoot the target floor.
			if landing.y >= _level_target.y:
				if randf() >= fall_pursuit_chance(cell.y - landing.y):
					return false  # it backs out this turn
				fall_down(brink)
				return true
	var link := _nearest_level_link(-1 if going_down else 1)
	if link == null:
		return false  # no way to reach that floor: it will move at random instead
	var approach: Vector3i = link.level_link_from()
	if cell == approach:
		# Stairs still have to be stepped into. An elevator has already done everything by being
		# stood on, so there is nothing more to do.
		if link.level_link_needs_step_in():
			return await _use_level_link(link)
		return false
	_target_cell = approach
	_has_target = true
	return false


## The most promising open edge to jump towards `toward`: a neighbouring cell over empty space,
## whose edge nothing bars (a GUARDRAIL protects it just as it protects the player), with floor
## somewhere below. Returns the current cell when no edge will do, and the rival stays on its
## floor. A bottomless hole is never picked — nobody jumps into one on purpose.
func _open_drop_edge(toward: Vector3i) -> Vector3i:
	var best := cell
	var best_score := 1 << 30
	for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		var n: Vector3i = cell + d
		if _dungeon.is_edge_blocked(cell, n) or _dungeon.is_floor(n):
			continue
		var landing: Vector3i = _dungeon.fall_landing(n)
		if landing == n:
			continue  # solid wall, or a bottomless hole
		var score: int = absi(landing.x - toward.x) + absi(landing.z - toward.z)
		if score < best_score:
			best_score = score
			best = n
	return best


## The chance, THIS TURN, of jumping off to give chase, once the cost of the fall is weighed.
## Since the roll is repeated at every opportunity, this weighting is what keeps the chase from
## becoming a near-certainty after a handful of turns.
##
## Three regimes: a painless fall (1 height unit) holds nobody back; a fall that would
## devitalise the rival is ALWAYS refused — a rival does not kill itself over a chase, and it
## would hand the player a free elimination; in between, the appetite drops with the share of
## its remaining density the fall would cost.
func fall_pursuit_chance(levels: int) -> float:
	var damage := DungeonManager.fall_damage(levels)
	if damage <= 0:
		return pursue_fall_chance
	if damage >= den:
		return 0.0
	var risk := float(damage) / float(den)
	return pursue_fall_chance * pow(1.0 - risk, fall_prudence)


## The nearest link (Manhattan distance) to another floor going the right way and reachable
## from the rival's floor. `direction` is +1 to go up, -1 to go down.
##
## Generic: stairs, an elevator, or any future mechanism implementing [DungeonMechanism]'s
## floor-change interface.
func _nearest_level_link(direction: int) -> Node:
	var best: Node = null
	var best_dist := 1 << 30
	for m in _dungeon.get_children():
		if not m.has_method("has_level_link") or not m.has_level_link():
			continue
		var from: Vector3i = m.level_link_from()
		var to: Vector3i = m.level_link_to()
		if from.y != cell.y or signi(to.y - from.y) != direction:
			continue
		if not _dungeon.is_floor(from):
			continue
		var d: Vector3i = (from - cell).abs()
		var dist: int = d.x + d.z
		if dist < best_dist:
			best_dist = dist
			best = m
	return best


func _stairs_at(c: Vector3i) -> Node:
	for m in _dungeon.mechanisms_at(c):
		if m.has_method("stairs_destination"):
			return m
	return null


## Takes the `link` from the current cell — a staircase to climb, and so on. Returns false when
## the destination is not walkable, or is occupied.
func _use_level_link(link) -> bool:
	var dest: Vector3i = link.level_link_to()
	if not _dungeon.is_floor(dest) or _dungeon.occupant_at(dest) != null:
		return false
	_dungeon.release(cell)
	_dungeon.reserve(dest, self)
	await _step_to(dest)
	if _dungeon == null:
		return true  # dissolved in the meantime
	_dungeon.notify_entered(dest, self)
	return true


## A fall from `from_cell`, chosen or not: lands on the floor below and takes the damage.
## Returns false when the rival is devitalised by it, and therefore dissolved.
func fall_down(from_cell: Vector3i) -> bool:
	var landing: Vector3i = _dungeon.fall_landing(from_cell)
	if landing == from_cell:
		# A bottomless hole (a level-design mistake): the rival vanishes into it, the way the duo
		# would be devitalised. Otherwise nothing below means no fall is possible.
		if _dungeon.is_bottomless(from_cell):
			queue_free()
			return false
		return true
	return drop_to(landing, from_cell.y - landing.y)


## Puts the rival on `target` at the end of a fall of `levels` floors and applies the damage.
## When `target` is occupied it lands on the nearest free cell instead: the one-occupant-per-
## cell invariant holds across the whole grid, and a fall is no reason to bend it. Returns
## false when the fall devitalises it.
func drop_to(target: Vector3i, levels: int) -> bool:
	var dest: Vector3i = _dungeon.free_cell_near(target)
	_dungeon.release(cell)
	_dungeon.reserve(dest, self)
	cell = dest
	# The cell changes at once, because the caller needs the result within the current turn, but
	# the descent is ANIMATED: without that the rival vanishes off the plank and reappears below,
	# and you never see that it fell.
	_busy = true
	var tween := create_tween()
	tween.tween_property(self, "global_position", _dungeon.cell_to_world(dest), 0.35)
	tween.finished.connect(func() -> void: _busy = false)
	if not apply_map_damage(DungeonManager.fall_damage(levels)):
		return false
	_dungeon.notify_entered(dest, self)
	return true


## Applies damage taken ON THE MAP, from a fall. The remaining DEN carries into the encounter
## that follows; at 0 the rival is devitalised where it stands and dissolved, with NO encounter,
## per the design doc. Returns true when the rival survives.
##
## A devitalisation ON THE MAP does NOT count as an encounter devitalisation: it feeds neither
## the FDE counter nor PSY (design decision, 2026-08-12). `GameSession.register_encounter_end`
## is deliberately not called here.
func apply_map_damage(amount: int) -> bool:
	den = maxi(den - amount, 0)
	if den > 0:
		return true
	_dissolve()
	return false


## Devitalised outside an encounter: the rival leaves the grid.
func _dissolve() -> void:
	_dungeon.release(cell)
	_dungeon.unregister_rival(self)
	_dungeon = null  # keeps _exit_tree from unregistering a second time
	queue_free()


## Two rivals meet on a plank: both fall, per the design doc — the occupant onto the cell
## below, the newcomer onto one adjacent to it.
func _collide_with_rival(tile: Vector3i, other: Node) -> void:
	var landing: Vector3i = _dungeon.fall_landing(tile)
	if landing == tile:
		return  # nothing empty under this plank: nobody falls
	var levels: int = tile.y - landing.y
	if other.has_method("drop_to"):
		other.drop_to(landing, levels)
	drop_to(_dungeon.free_cell_near(landing), levels)


## End of turn: elapses poison. A rival has no DEN on the map, so the effect is only counted
## down — the state will be handed to the encounter later on.
func on_turn_elapsed() -> void:
	affliction.tick_poison()


func _exit_tree() -> void:
	if _dungeon:
		_dungeon.release(cell)
		_dungeon.unregister_rival(self)
