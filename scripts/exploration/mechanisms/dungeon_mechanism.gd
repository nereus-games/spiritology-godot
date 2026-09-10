## Base of a dungeon mechanism sitting on the grid.
##
## A mechanism attaches to ONE tile and registers with the [DungeonManager] the way a
## [RivalBehavior] does, instead of being probed by scattered raycasts. Subclasses (Trap, and
## later Gateway, SpecialGround, Chest) override the hooks that concern them.
##
## No `class_name`: only the editor regenerates the global class cache and this game is
## launched from the command line, so this script is referenced by `preload` and by `extends`
## with a path. The [DungeonManager] drives mechanisms by duck typing — method calls — and
## depends on no global type.
extends Node3D

## The tile this mechanism sits on, derived from its world position at boot.
var tile: Vector3i

var _dungeon: DungeonManager


func _ready() -> void:
	add_to_group("dungeon_mechanism")
	_dungeon = get_tree().get_first_node_in_group("dungeon") as DungeonManager
	if _dungeon == null:
		push_error("[DungeonMechanism] no DungeonManager in the 'dungeon' group.")
		return
	tile = _dungeon.world_to_tile(global_position)
	_register()
	_on_registered()
	_spawn_visual()


## Registers with the dungeon. On the tile by default; overridden by mechanisms sitting on an
## EDGE between two tiles (gateways), which occupy no tile at all.
func _register() -> void:
	_dungeon.register_mechanism(tile, self)


## Symmetric to [method _register].
func _unregister() -> void:
	_dungeon.unregister_mechanism(tile, self)


## Subclass init hook, called once the tile is known and registration is done.
func _on_registered() -> void:
	pass


## Placeholder visual. Subclasses override it to drop a coloured marker they can pick out in
## a window. None by default.
func _spawn_visual() -> void:
	pass


var _marker: MeshInstance3D
## Marker height in metres, used to keep it resting on the floor when it is flattened.
var _marker_height := 0.0


## Drops a coloured box on the mechanism's tile. `height` and `size` are in METRES (a tile is
## [constant DungeonManager.TILE_SIZE] = 1 m). The node's origin is at the tile's floor (see
## [method DungeonManager.tile_to_world]), so the marker simply rests on it.
func _add_marker(color: Color, height := 0.6, size := 0.7) -> MeshInstance3D:
	return _add_marker_box(color, Vector3(size, height, size))


## Free-dimension variant (gateways are thin along one axis) with an optional local offset,
## for putting a visual on the tile's edge rather than at its centre.
func _add_marker_box(color: Color, size: Vector3, offset := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mi.material_override = mat
	mi.position = offset + Vector3(0.0, size.y * 0.5, 0.0)
	add_child(mi)
	_marker = mi
	_marker_height = size.y
	return mi


## How far a flattened marker is squashed — spent, or an open gateway.
const FLATTENED := 0.08

## The flat dark grey of a spent mechanism: a clear contrast with its active colour, and no
## emission — an active mechanism often lights itself.
const SPENT_COLOR := Color(0.24, 0.24, 0.27)


## Greys out and flattens the marker to show a SPENT mechanism — a sprung trap, an opened
## chest. It stays visible, as the design doc requires, but reads as clearly inert, nearly
## flush with the floor.
func _mark_spent() -> void:
	_grey_marker()
	_flatten_marker(true)


## Greys the marker WITHOUT flattening it, for a spent mechanism whose SHAPE still carries
## information — the die, which keeps its rolled face turned towards the player.
func _grey_marker() -> void:
	if _marker == null:
		return
	var mat := StandardMaterial3D.new()  # a fresh material also drops the active state's emission
	mat.albedo_color = SPENT_COLOR
	_marker.material_override = mat


## Removes the marker, for a mechanism that leaves NOTHING behind — recycled litter, where the
## tile becomes ordinary floor again and still drawing a heap there would be a lie.
func _remove_marker() -> void:
	if _marker == null:
		return
	_marker.queue_free()
	_marker = null
	_marker_height = 0.0


## Rebuilds the marker in its ACTIVE state, for rearming between visits.
func _respawn_marker() -> void:
	_remove_marker()
	_spawn_visual()


## Flattens the marker, or stands it back up, keeping it resting on the tile's floor.
func _flatten_marker(flat: bool) -> void:
	if _marker == null:
		return
	var f := FLATTENED if flat else 1.0
	_marker.scale.y = f
	_marker.position.y = _marker_height * f * 0.5


# --------------------------------------------------------------------------
# Framework hooks (overridden by subclasses; neutral defaults)
# --------------------------------------------------------------------------


## Whether the mechanism is SPENT — nothing left to get out of it: a sprung trap, an emptied
## chest, a rolled die, a used crystal. A cross-cutting rule: what is no longer actionable must
## no longer present itself as active, neither in 3D (a greyed marker, see [method _mark_spent])
## nor on the map ([ExplorationMinimap] dims these). Never spent by default — gateways,
## elevators, bridges and walls are endlessly reusable.
func is_spent() -> bool:
	return false


## Whether this mechanism shows on the MINI-MAP. Per the design doc's "User Interface", the
## map shows the current floor's mechanisms but NOT the traps — revealing them in advance would
## empty them of their point. Yes by default: gateways, chests and stairs are landmarks.
func shows_on_map() -> bool:
	return true


## Whether this mechanism makes the tile impassable (a closed gateway, an obstacle). Consulted
## by [method DungeonManager.is_walkable] and by the player's step.
func blocks_walk() -> bool:
	return false


## Whether this mechanism blocks SIGHT. By default what blocks passage blocks sight too — a
## wall, a closed gateway; a guardrail is low, and the exception. Used to forbid acting on
## whatever is BEHIND an opaque obstacle: you do not act on what you cannot see.
func blocks_sight() -> bool:
	return blocks_walk()


## An actor, player or rival, has just entered the tile. Where traps, chests, teleporters and
## elevators fire.
func on_enter(_who: Node) -> void:
	pass


## Per-turn tick, broadcast by [method DungeonManager.advance_turn] — automated gateways and
## the like.
func on_turn(_turn: int) -> void:
	pass


## Contextual actions when the actor is ON the tile, such as Dig on crumbly ground.
func on_tile_actions(_who: Node) -> Array:
	return []


## Contextual actions when the actor is ADJACENT and facing the tile — Recycle, Meditate,
## Refresh Crystal. `facing` is the tile delta being looked at.
func on_adjacent_actions(_who: Node, _facing: Vector3i) -> Array:
	return []


# --- Floor changes (stairs, elevators, and whatever comes next) ---
#
# The common interface the rivals' CHASE consults: when the player moves to another floor, a
# rival looks for a way up or down to it. Rather than knowing every mechanism, it asks these
# three hooks. A mechanism that leads nowhere keeps the defaults.


func has_level_link() -> bool:
	return false


## The tile it is taken from: the tile in front for stairs (you stand adjacent and step in),
## the platform itself for an elevator (standing on it is enough).
func level_link_from() -> Vector3i:
	return tile


func level_link_to() -> Vector3i:
	return tile


## Whether you have to STEP INTO the mechanism's tile from [method level_link_from] (stairs),
## or whether just arriving on that tile triggers the link (an elevator).
func level_link_needs_step_in() -> bool:
	return false


## Reset on entering a dungeon; this is what persistence between visits hangs off. No-op by
## default.
func reset_between_visits() -> void:
	pass


func _exit_tree() -> void:
	if _dungeon:
		_unregister()
