## A dungeon's logical grid: walkable tiles, occupancy, turns, rivals.
##
## The source of truth for navigation — not physics raycasts scattered around, the way the
## Unity prototype did it. The player and the rivals ASK this manager instead of probing the
## scene. A tile is a [Vector3i] (x, level y, z); world position is tile * TILE_SIZE.
##
## Exploration is turn-based: a player step calls [method advance_turn], which makes the
## rivals play. (Whether turning in place costs a turn would be wired in here — the design
## doc does not settle it, and the prototype counted it as a turn.)
##
## Found by the player and the rivals through the "dungeon" group.
##
## SCALE: 1 Godot unit = 1 metre. A tile — and so a wall block — is 1 m³, and the characters
## are small (eyes at [constant EYE_HEIGHT]), so a one-tile wall hides the view completely. A
## tile (x, y, z) spans from its FLOOR, at y * TILE_SIZE, up to one TILE_SIZE above it.
## [method tile_to_world] returns that floor: the point an actor stands on, and the origin
## mechanisms place their visuals against.
class_name DungeonManager
extends Node3D

const DungeonRenderer := preload("res://scripts/exploration/dungeon_renderer.gd")

## Tile size in world units (metres). A wall block is 1 m x 1 m x 1 m.
const TILE_SIZE := 1.0

## Eye height of a character, in metres. Below the height of a wall, so you never see over
## one. Applied by the player's camera rig (see `player.tscn`).
const EYE_HEIGHT := 0.6

## Thickness of a floor slab (which is also the ceiling of the tile below). Non-zero but
## thin: under an upper storey there is still TILE_SIZE - FLOOR_THICKNESS of headroom, plenty
## for a character about [constant EYE_HEIGHT] tall. A storey's floor is therefore NOT a solid
## block — you can walk under it wherever that level has a floor of its own.
##
## A slab is only laid where the floor overhangs EMPTY space or a walkable storey: above a
## wall block, the top face of the wall serves as the floor ("Walls + Decors" in the design
## doc: a wall can be stacked or serve as ground on the floor above it). That avoids doubling
## up the geometry and keeps level design lighter.
const FLOOR_THICKNESS := 0.1

## Thickness of anything sitting ON the edge between two tiles rather than on a tile — a
## [Gateway] or a guardrail. It occupies no tile, and stays thin enough for an actor to stand
## on either side.
const EDGE_THICKNESS := 0.1


## Damage taken from falling `levels` height units.
##
## From the design doc ("Mechanisms + Heights"): when jumping down 2+ height units, both
## player characters get 10 damage, plus 5 damage per additional height unit. A fall of a
## SINGLE unit therefore costs nothing. It is a shared dungeon rule — rivals take it too.
static func fall_damage(levels: int) -> int:
	if levels < 2:
		return 0
	return 10 + 5 * (levels - 2)


signal turn_advanced(turn: int)
## Emitted when a move lands on a tile held by an opposing individual.
signal encounter_requested(rival: Node, initiated_by_rival: bool)

## A rival steps onto the narrow-bridge tile the player is on: both fall.
signal bridge_collision(rival: Node, tile: Vector3i)

## A one-off message for the player (the outcome of a dieverting; later on a sprung trap, an
## object found). Mechanisms post it through [method post_message] and the HUD shows it — a
## mechanism has no business knowing about the UI.
signal message_posted(text: String)

## Scaffolding: builds a rectangular room at boot so the exploration loop can be tested
## without authored dungeons. Set demo_build=false for a real dungeon, whose grid comes from
## somewhere else.
@export var demo_build := false
@export var demo_width := 9
@export var demo_depth := 9
@export var demo_interior_walls: Array[Vector3i] = []

var turn_count := 0

# Walkable tiles (floor). tile:Vector3i -> true.
var _floor: Dictionary = {}
# Occupancy: tile:Vector3i -> Node (a rival). The player does NOT occupy a tile — stepping
# onto an occupied one starts an encounter instead.
var _occupants: Dictionary = {}

# Mechanisms per tile: tile:Vector3i -> Array of mechanisms. Several can share one tile.
# Registered by the mechanism nodes themselves at boot.
var _mechanisms: Dictionary = {}

# Tiles rendered as wall blocks, remembered by [method render_grid]. The mini-map draws them:
# a room reads by its outline, not only by the absence of floor.
var _walls: Dictionary = {}

# EDGE mechanisms (gateways): on no tile at all, but on the boundary between two neighbouring
# tiles. Canonical [method edge_key] -> Array of mechanisms.
var _edge_mechanisms: Dictionary = {}

# Tiles explicitly left EMPTY — a deliberate hole from the level design. Never rendered as a
# wall, even with nothing holding them up. Entering one is a BOTTOMLESS fall, and fatal (see
# [method is_bottomless]). A merely absent tile still becomes a wall: that is the normal case
# around the outside of a room.
var _hole: Dictionary = {}

# Pit tiles (a floor set LOWER, a ravine): rendered as a lowered dark slab, never as a wall,
# and with no normal slab when the tile is walkable too — that is the bridge plank laid over
# it. Gives the "log over a drop" look.
var _pit: Dictionary = {}
## How far (metres) a pit slab sits below the normal floor level.
const PIT_DEPTH := 1.2

var _player: Node3D
var _rivals: Array[Node] = []


func _ready() -> void:
	add_to_group("dungeon")
	if demo_build:
		build_demo_room(demo_width, demo_depth, demo_interior_walls)


# --------------------------------------------------------------------------
# World <-> grid conversions
# --------------------------------------------------------------------------


func world_to_tile(pos: Vector3) -> Vector3i:
	return Vector3i(roundi(pos.x / TILE_SIZE), roundi(pos.y / TILE_SIZE), roundi(pos.z / TILE_SIZE))


## World point at the tile's FLOOR, centred: where an actor's feet go. The tile's volume runs
## from there up to [constant TILE_SIZE] above.
func tile_to_world(tile: Vector3i) -> Vector3:
	return Vector3(tile.x, tile.y, tile.z) * TILE_SIZE


# --------------------------------------------------------------------------
# Walkability & occupancy
# --------------------------------------------------------------------------


func is_floor(tile: Vector3i) -> bool:
	return _floor.has(tile)


## Says NOTHING about gateways, which block an edge rather than a tile — for an actual step,
## go through [method can_step].
func is_walkable(tile: Vector3i) -> bool:
	return _floor.has(tile) and not _occupants.has(tile) and not is_blocked_by_mechanism(tile)


## Whether a step from `from_tile` to a neighbouring `to_tile` is possible: the destination is
## walkable AND the edge between them is not blocked by a closed gateway.
func can_step(from_tile: Vector3i, to_tile: Vector3i) -> bool:
	return is_walkable(to_tile) and not is_edge_blocked(from_tile, to_tile)


## Whether a mechanism on the tile forbids passage. Independent of occupancy.
func is_blocked_by_mechanism(tile: Vector3i) -> bool:
	for m in mechanisms_at(tile):
		if m.blocks_walk():
			return true
	return false


func occupant_at(tile: Vector3i) -> Node:
	return _occupants.get(tile)


func reserve(tile: Vector3i, who: Node) -> bool:
	if not _floor.has(tile) or _occupants.has(tile):
		return false
	_occupants[tile] = who
	return true


func release(tile: Vector3i) -> void:
	_occupants.erase(tile)


func move_occupant(from_tile: Vector3i, to_tile: Vector3i, who: Node) -> bool:
	if not can_step(from_tile, to_tile):
		return false
	_occupants.erase(from_tile)
	_occupants[to_tile] = who
	return true


# --------------------------------------------------------------------------
# Actors & turns
# --------------------------------------------------------------------------


func register_player(player: Node3D) -> void:
	_player = player


func player_tile() -> Vector3i:
	return world_to_tile(_player.global_position) if _player else Vector3i.ZERO


## For mechanisms that only apply to the player — chest loot, dieverting.
func is_player(who: Node) -> bool:
	return who != null and who == _player


## Whether the rivals should ignore the player — hidden or unchased through fog mantel,
## torment veil, a costume. Consulted by rival detection.
func rivals_ignore_player() -> bool:
	return (
		is_instance_valid(_player)
		and _player.has_method("is_hidden_from_rivals")
		and _player.is_hidden_from_rivals()
	)


func register_rival(rival: Node) -> void:
	if rival in _rivals:
		return
	_rivals.append(rival)
	reserve(world_to_tile(rival.global_position), rival)


func unregister_rival(rival: Node) -> void:
	_rivals.erase(rival)


## Advances one turn: notifies, makes every rival play, then ticks the mechanisms and lets
## afflictions such as poison elapse. The single integration point of the turn model, called
## by the player after a successful step.
##
## ## TODO: the design doc's turn order has FOUR phases — "player, then reveal of dungeon
## mechanisms (traps), then other spirimonsters, then dungeon mechanisms activation". The
## REVEAL phase is missing here, and belongs BEFORE the rivals play: today a trap only comes
## to light by springing ([code]trap.on_enter[/code] sets `revealed`), and
## [code]trap.reveal()[/code] has no call site at all. That phase is where the `reveal_traps`
## talent (razél) and `trick_to_reveal` (érzélak) are meant to hook in.
func advance_turn() -> void:
	turn_count += 1
	turn_advanced.emit(turn_count)
	var ptile := player_tile()
	for rival in _rivals.duplicate():
		if is_instance_valid(rival) and rival.has_method("take_turn"):
			rival.take_turn(ptile)
	# Ticked mechanisms (automated gateways and the like), on tiles and on edges alike.
	for dict in [_mechanisms, _edge_mechanisms]:
		for arr in dict.values():
			for m in arr:
				if is_instance_valid(m):
					m.on_turn(turn_count)
	# Per-actor lingering effects (poison), after the rivals have played.
	_tick_actor_afflictions()


## Elapses the player's and the rivals' afflictions. Each actor applies its own effect
## (poison hits DEN), which keeps the manager decoupled from them.
func _tick_actor_afflictions() -> void:
	if is_instance_valid(_player) and _player.has_method("on_turn_elapsed"):
		_player.on_turn_elapsed()
	for rival in _rivals.duplicate():
		if is_instance_valid(rival) and rival.has_method("on_turn_elapsed"):
			rival.on_turn_elapsed()


## Posts a feedback message for the player. The text is expected to be ALREADY translated.
func post_message(text: String) -> void:
	message_posted.emit(text)


func request_encounter(rival: Node, initiated_by_rival: bool) -> void:
	encounter_requested.emit(rival, initiated_by_rival)


## Two characters meet on the SAME narrow-bridge tile: both fall, per the design doc. The
## player-versus-rival case is arbitrated by `exploration.gd`, which drives the player's
## crossing.
func request_bridge_collision(rival: Node, tile: Vector3i) -> void:
	bridge_collision.emit(rival, tile)


## Registered rivals, as a copy — the caller is free to dissolve some while iterating.
func rivals() -> Array[Node]:
	return _rivals.duplicate()


## An actor has CHANGED FLOOR — a fall, stairs, tomorrow an elevator or anything else. The
## rivals that saw it leave can then chase it by their own means.
##
## The single broadcast point: any mechanism that moves the player between floors goes through
## here rather than notifying the rivals itself.
func notify_level_change(who: Node, from_tile: Vector3i, to_tile: Vector3i) -> void:
	if not is_player(who):
		return
	for rival in _rivals.duplicate():
		if is_instance_valid(rival) and rival.has_method("witness_player_level_change"):
			rival.witness_player_level_change(from_tile, to_tile)


## Whether the tile is a narrow bridge, recognised by a mechanism exposing the balance test.
func is_narrow_bridge(tile: Vector3i) -> bool:
	for m in mechanisms_at(tile):
		if m.has_method("engage") and m.has_method("direction"):
			return true
	return false


## The nearest free floor tile to `tile` (`tile` itself if it is free), for placing an actor
## without breaking the one-occupant-per-tile invariant. Returns `tile` when nothing around is
## free, and leaves the caller to decide what that means.
func free_tile_near(tile: Vector3i) -> Vector3i:
	if is_floor(tile) and occupant_at(tile) == null:
		return tile
	for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		var n: Vector3i = tile + d
		if is_walkable(n) and occupant_at(n) == null:
			return n
	return tile


## Free floor tiles AROUND `tile`, on the same floor, within `radius` tiles (Manhattan
## distance), shuffled. `tile` itself is excluded. Lets actors be spawned "nearby" without
## caring about the shape of the room.
func free_tiles_near(tile: Vector3i, radius: int) -> Array[Vector3i]:
	var found: Array[Vector3i] = []
	for dx in range(-radius, radius + 1):
		for dz in range(-radius, radius + 1):
			if absi(dx) + absi(dz) > radius or (dx == 0 and dz == 0):
				continue
			var c := tile + Vector3i(dx, 0, dz)
			if is_walkable(c) and occupant_at(c) == null:
				found.append(c)
	found.shuffle()
	return found


# --------------------------------------------------------------------------
# Dungeon mechanisms (traps, gateways, special floors)
# --------------------------------------------------------------------------


## Registers a mechanism on a tile. Called by the mechanism node itself at boot.
func register_mechanism(tile: Vector3i, mechanism: Node) -> void:
	var arr: Array = _mechanisms.get(tile, [])
	if mechanism not in arr:
		arr.append(mechanism)
	_mechanisms[tile] = arr


func unregister_mechanism(tile: Vector3i, mechanism: Node) -> void:
	var arr: Array = _mechanisms.get(tile, [])
	arr.erase(mechanism)
	if arr.is_empty():
		_mechanisms.erase(tile)
	else:
		_mechanisms[tile] = arr


func mechanisms_at(tile: Vector3i) -> Array:
	return _mechanisms.get(tile, [])


# --------------------------------------------------------------------------
# Edge mechanisms (gateways) — between tiles, not on one
# --------------------------------------------------------------------------


## Canonical key for the edge between two neighbouring tiles: order-independent, so the same
## from either side. Vector4i(x, y, z, axis), where (x, y, z) is the lower of the two tiles
## along that axis and axis is 0 for an X boundary, 1 for a Z one.
static func edge_key(from_tile: Vector3i, to_tile: Vector3i) -> Vector4i:
	var lo := from_tile
	var d := to_tile - from_tile
	if d.x + d.z < 0:
		lo = to_tile
		d = -d
	var axis := 0 if d.x != 0 else 1
	return Vector4i(lo.x, lo.y, lo.z, axis)


## Registers a mechanism on the edge between two tiles. Called by the node itself at boot.
func register_edge_mechanism(from_tile: Vector3i, to_tile: Vector3i, mechanism: Node) -> void:
	var key := edge_key(from_tile, to_tile)
	var arr: Array = _edge_mechanisms.get(key, [])
	if mechanism not in arr:
		arr.append(mechanism)
	_edge_mechanisms[key] = arr


func unregister_edge_mechanism(from_tile: Vector3i, to_tile: Vector3i, mechanism: Node) -> void:
	var key := edge_key(from_tile, to_tile)
	var arr: Array = _edge_mechanisms.get(key, [])
	arr.erase(mechanism)
	if arr.is_empty():
		_edge_mechanisms.erase(key)
	else:
		_edge_mechanisms[key] = arr


func edge_mechanisms_between(from_tile: Vector3i, to_tile: Vector3i) -> Array:
	return _edge_mechanisms.get(edge_key(from_tile, to_tile), [])


## Whether the step from a tile to its neighbour is barred (closed gateway, guardrail).
## Symmetric.
func is_edge_blocked(from_tile: Vector3i, to_tile: Vector3i) -> bool:
	for m in edge_mechanisms_between(from_tile, to_tile):
		if m.blocks_walk():
			return true
	return false


## Whether the edge is OPAQUE (a closed gateway). A guardrail bars the step but not the view.
func is_edge_opaque(from_tile: Vector3i, to_tile: Vector3i) -> bool:
	for m in edge_mechanisms_between(from_tile, to_tile):
		if m.blocks_sight():
			return true
	return false


## Tells a tile's mechanisms that an actor entered it — this is what springs traps. Called by
## the player and by the rivals once a step has logically gone through.
func notify_entered(tile: Vector3i, who: Node) -> void:
	for m in mechanisms_at(tile).duplicate():
		if is_instance_valid(m):
			m.on_enter(who)


## The contextual actions open to an actor standing on `from_tile` and looking at `facing`.
## Aggregates the on-tile actions of the mechanisms on `from_tile` (Dig), the adjacent actions
## of the mechanisms on the tile being looked at, `from_tile + facing` (Recycle, Examine), and
## those of the mechanisms sitting on the edge being looked at — a gateway can be opened or
## meditated at from either side. Consumed by the exploration action surface (the HUD).
func actions_for(from_tile: Vector3i, facing: Vector3i, who: Node) -> Array:
	var actions: Array = []
	for m in mechanisms_at(from_tile):
		actions.append_array(m.on_tile_actions(who))
	for m in edge_mechanisms_between(from_tile, from_tile + facing):
		actions.append_array(m.on_adjacent_actions(who, facing))
	# Whatever blocks sight blocks interaction: nothing BEHIND a closed gateway is actionable.
	# The gateway's own actions stay on offer, of course — it is the thing being acted on. Over
	# a guardrail, by contrast, you both see and act.
	if is_edge_opaque(from_tile, from_tile + facing):
		return actions
	for m in mechanisms_at(from_tile + facing):
		actions.append_array(m.on_adjacent_actions(who, facing))
	return actions


## A random walkable floor tile other than `exclude`. Returns `exclude` when there is none.
func random_floor_tile(exclude: Vector3i) -> Vector3i:
	var candidates: Array = []
	for c in _floor:
		if c != exclude and is_walkable(c):
			candidates.append(c)
	if candidates.is_empty():
		return exclude
	return candidates[randi() % candidates.size()]


## Teleports an actor to a random free floor tile — the teleport trap. Returns the tile it
## landed on, unchanged when no destination was free.
func teleport_actor(who: Node) -> Vector3i:
	var from: Vector3i = who.tile
	return teleport_actor_to(who, random_floor_tile(from))


## Teleports an actor to a SPECIFIC tile — a dungeon entrance or exit, a dieverting. Falls
## back to a free neighbouring tile when the destination is occupied, and keeps occupancy
## straight (rivals occupy their tile, the player does not). Returns the tile it landed on,
## unchanged when the destination is not walkable. Does NOT fire the destination's mechanisms:
## this is an instant relocation.
func teleport_actor_to(who: Node, dest: Vector3i) -> Vector3i:
	var from: Vector3i = who.tile
	if not is_floor(dest):
		return from
	dest = free_tile_near(dest)
	if dest == from:
		return from
	var occ := occupant_at(dest)
	if occ != null and occ != who:
		return from  # nothing free at the destination, and we will not evict anyone
	if _occupants.get(from) == who:
		_occupants.erase(from)
		_occupants[dest] = who
	if who.has_method("teleport_to"):
		who.teleport_to(dest)
	return dest


# --------------------------------------------------------------------------
# Dungeon entrance & exits
# --------------------------------------------------------------------------
#
# Per the design doc ("Dungeons"), you leave a dungeon by reaching an EXIT and interacting
# with it, and "the dungeon entry counts as an exit point". These tiles are declared by level
# design — in dev, by the test scenario. Today they serve the mechanisms that send the player
# back to them, such as dieverting.
# ## TODO: leaving the dungeon proper — the interaction, returning to the world map, exiting
# after the duo is devitalised — is still unwired. See `exploration.gd`.

var _entrance: Vector3i
var _has_entrance := false
var _exits: Array[Vector3i] = []


## Declares the entrance tile. It ALSO counts as an exit, per the design doc, so there is no
## need to add it twice.
func set_entrance(tile: Vector3i) -> void:
	_entrance = tile
	_has_entrance = true
	add_exit(tile)


func has_entrance() -> bool:
	return _has_entrance


## The dungeon's entrance tile — Vector3i.ZERO while none has been declared, so check
## [method has_entrance] before using it.
func entrance_tile() -> Vector3i:
	return _entrance


func add_exit(tile: Vector3i) -> void:
	if tile not in _exits:
		_exits.append(tile)


func exit_tiles() -> Array[Vector3i]:
	return _exits.duplicate()


func has_exit() -> bool:
	return not _exits.is_empty()


## A random exit — the design doc says "at random if more than one". Returns Vector3i.ZERO
## when none is declared, so check [method has_exit] first.
func random_exit() -> Vector3i:
	if _exits.is_empty():
		return Vector3i.ZERO
	return _exits[randi() % _exits.size()]


# --------------------------------------------------------------------------
# Building the grid
# --------------------------------------------------------------------------


func set_floor_tiles(tiles: Array) -> void:
	_floor.clear()
	for c in tiles:
		_floor[c] = true


func add_floor(tile: Vector3i) -> void:
	_floor[tile] = true


## Marks a tile as a pit: walkable, but [method render_grid] lays NEITHER a normal slab NOR a
## wall there — the tile is held up only by whatever level design puts on it, a bridge plank.
## With no real floor underneath, a dark slab is laid below so the gap does not read as a void;
## otherwise the floor below serves as the bottom.
func mark_pit(tile: Vector3i) -> void:
	_pit[tile] = true


## Marks a tile as an outright hole: no wall to plug it, and no bottom either.
func mark_hole(tile: Vector3i) -> void:
	_hole[tile] = true


func is_hole(tile: Vector3i) -> bool:
	return _hole.has(tile)


## Whether entering this tile means a BOTTOMLESS fall. Such a fall should not exist — it would
## be a level-design mistake — because the outside of a room is rendered as wall precisely
## since nothing holds it up. If level design leaves one anyway, it is treated as what it is,
## a floor too far down to survive: a fatal fall, rather than a silent block.
func is_bottomless(tile: Vector3i) -> bool:
	return _hole.has(tile) and not _floor.has(tile) and fall_landing(tile) == tile


## Where a fall from `tile` lands: the first FLOOR tile below it. Returns `tile` unchanged
## when there is none, which means no fall at all — a wall.
func fall_landing(tile: Vector3i) -> Vector3i:
	for level in range(tile.y - 1, tile.y - 12, -1):
		var below := Vector3i(tile.x, level, tile.z)
		if _floor.has(below):
			return below
	return tile


## The logical grid's floor tiles (tile -> true). Read-only: this is the live dictionary.
func floor_tiles() -> Dictionary:
	return _floor


## Tiles marked as pits (tile -> true). Read-only: this is the live dictionary.
func pit_tiles() -> Dictionary:
	return _pit


## Builds the visible geometry from the logical grid. The drawing itself lives in
## [DungeonRenderer]: this manager holds the MODEL, not the meshes.
func render_grid() -> void:
	# Remembered for the mini-map, which redraws them every frame.
	_walls = derive_wall_tiles()
	DungeonRenderer.render_grid(self, _walls)


## Tiles rendered as wall blocks. Empty until [method render_grid] has run.
func wall_tiles() -> Dictionary:
	return _walls


func is_wall(tile: Vector3i) -> bool:
	return _walls.has(tile)


## TODO (2026-09-02) — AUTHORING DEBT. Walls and holes are today DERIVED from the floor grid
## alone: a wall is "nothing here, and nothing below", and an outright hole only exists if
## someone calls [method mark_hole] — nobody does, outside the headless check. Two rules from
## the design doc therefore rest on inference rather than declaration:
##  - "a wall can serve as ground on the floor above it" (no slab above a wall);
##  - "if an endless fall happens anyway, it devitalises" (the outright hole).
## Once a dungeon authoring format exists, walls and holes will have to be DECLARED the way
## floors are, and [method derive_wall_tiles] will be scaffolding for code-built test
## scenarios only.
##
## Tiles rendered as wall blocks: non-floor tiles next to floor, carrying no mechanism and no
## pit, with no floor below them — the lip of a drop stays open rather than being walled off.
##
## Public because it is a query on the MODEL ("where does the grid imply a wall?") rather than
## a rendering matter: the geometry checks assert against it.
func derive_wall_tiles() -> Dictionary:
	var wall_tiles := {}
	for c in _floor:
		for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			var n: Vector3i = c + d
			if _hole.has(n):
				continue  # a deliberate hole: on no account wall it off
			if (
				not _floor.has(n)
				and not _mechanisms.has(n)
				and not _pit.has(n)
				and fall_landing(n) == n
			):
				wall_tiles[n] = true
	return wall_tiles


## Builds a demo room: a rectangular floor at level 0 with a few interior walls, and renders
## it. Scaffolding — real dungeons will be authored 3D scenes.
func build_demo_room(width: int, depth: int, interior_walls: Array = []) -> void:
	var blocked := {}
	for w in interior_walls:
		blocked[w] = true
	var tiles: Array = []
	for x in range(width):
		for z in range(depth):
			var c := Vector3i(x, 0, z)
			if not blocked.has(c):
				tiles.append(c)
	set_floor_tiles(tiles)
	DungeonRenderer.build_demo_visuals(self, width, depth, blocked)
