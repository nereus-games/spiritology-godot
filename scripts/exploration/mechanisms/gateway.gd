## A dungeon gateway: automated, locked, meditation, or teleport.
##
## Per the design doc ("Mechanisms / Gateways") these are SLIDING doors. A gateway therefore
## occupies NO tile: it sits on the EDGE between two neighbouring tiles — the anchor
## [member tile] and its neighbour along [member edge_dir] — and bars that passage while it is
## closed ([method blocks_walk]). Being thin
## ([constant DungeonManager.EDGE_THICKNESS]) it leaves room to stand on either side, so it can
## be faced from both, and its actions (open, meditate) are available from both.
##
## Four kinds:
##  - AUTOMATED: opens and closes along a fixed pattern cycled every turn (3 turns by default:
##    closed, closed, open). The pattern can differ per gateway ([member phase_offset]).
##  - LOCKED: opens in exchange for objects, and stays open. An alternative to a dangerous route
##    at the cost of resources. The design doc's "OR" (early = 2 spades or 4 rune stones; late =
##    4 spades or 6 rune stones) is a LEVEL DESIGN choice, not an alternative offered to the
##    player: each gateway demands ONE currency ([member cost_currency]), whose amount follows
##    from the tier ([member cost_tier]).
##  - MEDITATION: opens after N CONSECUTIVE meditations in front of it, and stays open.
##    "Consecutive", in the design doc's sense, means with nothing else done in between: the
##    streak drops as soon as a turn elapses while the player has left the tile they were
##    meditating from, or turned away from the gateway.
##  - TELEPORT: cycles like an automated one, but is NOT a sliding door: it never leaves a
##    passage between its two tiles, open or closed ([method blocks_walk] is always true). Going
##    through it while it is open sends the individual, player or rival, to a fixed
##    [member arrival_tile] elsewhere — see [method admits_from] and [method send_through].
##    Either set against a wall and entered from the
##    anchor tile only, or on the border between two floor tiles and entered from both
##    ([member two_sided]), leading to the same arrival tile either way. The arrival tile has no
##    gate of its own, so the trip is one way.
##
## No `class_name` (see dungeon_mechanism.gd): `extends` by path. The player actions — unlocking
## a locked gateway, meditating — are public methods, and reach the HUD's contextual menu
## through [method DungeonManager.actions_for].
extends "res://scripts/exploration/mechanisms/dungeon_mechanism.gd"

const ExplorationAction := preload("res://scripts/exploration/exploration_action.gd")

enum Kind { AUTOMATED, LOCKED, MEDITATION, TELEPORT }

## Dungeon tier, which sets what a locked gateway costs.
enum CostTier { EARLY, LATE }

## The opening-cost scale, per tier and per currency. Level design picks each gateway's
## currency; this table only gives the rate. Object slugs as generated in `data/objects/`.
const LOCKED_COSTS := {
	CostTier.EARLY: {&"spade": 2, &"rune_stone": 4},
	CostTier.LATE: {&"spade": 4, &"rune_stone": 6},
}

@export var kind: Kind = Kind.AUTOMATED

## The neighbour being barred: the gateway sits on the edge between [member tile] and
## `tile + edge_dir`. Always a unit horizontal direction (±X or ±Z).
@export var edge_dir := Vector3i(0, 0, 1)

## AUTOMATED and TELEPORT: the cycled opening pattern, one boolean per turn. The design doc's
## default is closed / closed / open, for both.
@export var open_pattern: Array[bool] = [false, false, true]
## AUTOMATED and TELEPORT: phase offset, so two gateways need not be in sync.
@export var phase_offset := 0

## TELEPORT: where going through sends you. An ordinary floor tile anywhere in the dungeon,
## other floors included. Nothing tells the player where it is: they find out by going through.
@export var arrival_tile := Vector3i.ZERO

## TELEPORT: entered from both sides, rather than from the anchor [member tile] alone. False for
## a gate set against a wall, whose [member edge_dir] then points at the wall.
@export var two_sided := false

## LOCKED: cost tier, which fixes the AMOUNT demanded.
@export var cost_tier: CostTier = CostTier.EARLY

## LOCKED: the currency THIS gateway demands, settled by level design. Together with
## [member cost_tier] it fully determines the price (see [method locked_cost]).
@export var cost_currency: StringName = &"spade"

## MEDITATION: how many meditations it takes to open.
@export var meditations_required := 3

var _open := false
var _meditations := 0

# The meditation streak in progress: the tile the player is meditating from and the direction
# they face. Checked every turn to confirm they are STILL there — otherwise the streak breaks.
var _streak_tile := Vector3i.ZERO
var _streak_facing := Vector3i.ZERO
var _streak_open := false


## On the edge, not on the tile: the anchor tile stays walkable.
func _register() -> void:
	_dungeon.register_edge_mechanism(tile, tile + edge_dir, self)


func _unregister() -> void:
	_dungeon.unregister_edge_mechanism(tile, tile + edge_dir, self)


func _on_registered() -> void:
	# A cycling gateway starts on the pattern's first value, offset included.
	if _cycles() and not open_pattern.is_empty():
		_open = open_pattern[phase_offset % open_pattern.size()]


## Whether the gateway opens and closes on its own, turn after turn.
func _cycles() -> bool:
	return kind == Kind.AUTOMATED or kind == Kind.TELEPORT


## A closed gateway bars the edge it sits on; a teleport gate bars it even open — it is a way
## out, not a way through. Consulted by [method DungeonManager.is_edge_blocked].
func blocks_walk() -> bool:
	return kind == Kind.TELEPORT or not _open


func is_open() -> bool:
	return _open


func is_teleport() -> bool:
	return kind == Kind.TELEPORT


## Whether an individual standing on `from_tile` can go through this teleport gate right now:
## it is open, and `from_tile` is a side it is entered from.
func admits_from(from_tile: Vector3i) -> bool:
	if kind != Kind.TELEPORT or not _open:
		return false
	return from_tile == tile or (two_sided and from_tile == tile + edge_dir)


## The teleport gate on the edge between two neighbouring tiles of `dungeon`, or null. Static
## so that the player and the rivals can ask without the [DungeonManager] growing a method.
static func teleport_gate_between(dungeon, from_tile: Vector3i, to_tile: Vector3i) -> Node:
	for m in dungeon.edge_mechanisms_between(from_tile, to_tile):
		if m.has_method("is_teleport") and m.is_teleport():
			return m
	return null


const NEIGHBOURS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)
]


## Sends `who` through this teleport gate, to [member arrival_tile]. Per the design doc the trip
## happens even when the arrival tile is taken:
##  - the player arriving on a rival, or a rival arriving on the player, starts an encounter;
##  - a rival group arriving on another pushes the one already there aside
##    (see [method _push_group]).
## Returns true when an encounter was requested — the caller's move ends there, as it does when
## walking into a rival. Otherwise the caller resolves the arrival as after any step: the tile's
## mechanisms, then the turn. Does not check that the gate admits `who`: see [method admits_from].
func send_through(who: Node) -> bool:
	var from: Vector3i = who.tile
	var arrival := arrival_tile
	if _dungeon == null or not _dungeon.is_floor(arrival) or arrival == from:
		return false
	if _dungeon.is_player(who):
		_dungeon.notify_level_change(who, from, arrival)  # watching rivals can follow
		who.teleport_to(arrival)
		var met: Node = _dungeon.occupant_at(arrival)
		if met != null:
			_dungeon.request_encounter(met, false)
			return true
		return false
	var there: Node = _dungeon.occupant_at(arrival)
	if there != null and there != who and not _push_group(there, {who: true}):
		# Nowhere to push the group already there — not even onto a trap, over a ledge, or into a
		# neighbouring group. Some rival has to go somewhere, and it is the newcomer.
		push_warning("[Gateway] %s: nowhere to push a rival group aside." % arrival)
		_dungeon.teleport_actor(who)
		return false
	if _dungeon.occupant_at(from) == who:
		_dungeon.release(from)
	_dungeon.reserve(arrival, who)
	who.teleport_to(arrival)
	if arrival == _dungeon.player_tile():
		_dungeon.request_encounter(who, true)
		return true
	return false


## Pushes the rival `group` off its tile onto a neighbouring one, to make room for a group
## arriving through this gate. The design doc's order of preference: an ORDINARY free tile;
## failing that, a trap, or a ledge with no railing to fall from; failing that, the group next to
## it is pushed in turn and this one takes its place. Never onto the player, and never into a
## safe area. `pushing` holds the groups already in the chain, so it cannot loop. Returns false
## when the group could not be moved at all.
func _push_group(group: Node, pushing: Dictionary) -> bool:
	pushing[group] = true
	var at: Vector3i = group.tile
	var safe = _dungeon.safe_areas
	var around: Array[Vector3i] = []
	for d in NEIGHBOURS:
		var n: Vector3i = at + d
		if not _dungeon.is_edge_blocked(at, n) and n != _dungeon.player_tile() and not safe.has(n):
			around.append(n)
	# An ordinary free tile: floor, nobody on it, nothing on it.
	for n in around:
		if _dungeon.is_walkable(n) and _dungeon.mechanisms_at(n).is_empty():
			_shove(group, n)
			return true
	# A free tile carrying a mechanism — a trap, typically — which fires on arrival.
	for n in around:
		if _dungeon.is_walkable(n):
			_shove(group, n)
			_dungeon.notify_entered(n, group)
			return true
	# A ledge: no floor there, but some further down. The group falls, and takes the damage.
	for n in around:
		var landing: Vector3i = _dungeon.fall_landing(n)
		if not _dungeon.is_floor(n) and landing != n and not safe.has(landing):
			if group.has_method("fall_down"):
				group.fall_down(n)
				return true
	# The group next to it, pushed in turn.
	for n in around:
		var next_group: Node = _dungeon.occupant_at(n)
		if next_group != null and not pushing.has(next_group) and _push_group(next_group, pushing):
			_shove(group, n)
			return true
	return false


func _shove(group: Node, to_tile: Vector3i) -> void:
	_dungeon.release(group.tile)
	_dungeon.reserve(to_tile, group)
	group.teleport_to(to_tile)


## What is on offer when FACING the gateway, from either side: paying to open a locked one, or
## meditating in front of a meditation one, while they are closed. Automated gateways offer
## nothing — they cycle on their own.
func on_adjacent_actions(who: Node, facing: Vector3i) -> Array:
	if _open:
		return []
	if kind == Kind.LOCKED:
		return [
			ExplorationAction.new(
				&"open_gate", "UI_ACTION_OPEN_GATE", Callable(self, "try_open_locked")
			)
		]
	if kind == Kind.MEDITATION:
		# The tile and the direction are frozen into the action: THAT is where the meditation
		# counts from, and the spot that has to be held to keep the streak going.
		var from_tile: Vector3i = who.tile if who != null and "tile" in who else tile
		return [
			ExplorationAction.new(
				&"meditate",
				"UI_ACTION_MEDITATE",
				Callable(self, "meditate").bind(from_tile, facing)
			)
		]
	return []


func on_turn(turn: int) -> void:
	# Only automated and teleport gateways cycle; LOCKED and MEDITATION ones stay open once opened.
	if _cycles() and not open_pattern.is_empty():
		# A gateway lives between tiles, so it can never close ON the player — they are always on
		# one side or the other — and the pattern applies as-is.
		_open = open_pattern[(turn + phase_offset) % open_pattern.size()]
		_update_marker()
	elif kind == Kind.MEDITATION and _streak_open and not _open:
		# A turn has just elapsed: the streak only holds if the player has not left their spot —
		# by walking, falling or being teleported — nor looked away.
		if not _player_holds_post():
			_break_streak()


## Whether the player is still on the tile they meditated from, turned towards this gateway.
func _player_holds_post() -> bool:
	if _dungeon == null or _dungeon.player_tile() != _streak_tile:
		return false
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not player.has_method("facing_delta"):
		return true  # unknown facing: do not break the streak on a doubt
	return player.facing_delta() == _streak_facing


## Breaks the streak in progress: the counter goes back to zero, and the label with it.
func _break_streak() -> void:
	_streak_open = false
	if _meditations == 0:
		return
	_meditations = 0
	_update_gate_label()


## This gateway's price: how much [member cost_currency] the [member cost_tier] demands. 0 when
## it is not a locked gateway, or when the currency set on it has no rate in the table — a level
## design mistake, since the gateway would then be impassable.
func locked_cost() -> int:
	if kind != Kind.LOCKED:
		return 0
	return LOCKED_COSTS[cost_tier].get(cost_currency, 0)


## Tries to open a locked gateway by paying its price. A gateway demands ONE currency, chosen by
## level design, so the player has nothing to weigh up. Consumes the objects and opens if they
## can pay. Returns `true` when the gateway ends up open.
func try_open_locked() -> bool:
	if kind != Kind.LOCKED:
		return _open
	if _open:
		return true
	var need := locked_cost()
	if need <= 0 or GameSession.object_count(cost_currency) < need:
		return false
	GameSession.remove_object(cost_currency, need)
	_open = true
	_update_marker()
	_update_gate_label()
	return true


## Counts one meditation in front of a meditation gateway, made from `from_tile` while looking
## at `facing`. Opens the gateway on the Nth ([member meditations_required]) — provided the
## meditations are CONSECUTIVE: moving between two resets the count (see [method on_turn]).
## Returns `true` when the gateway ends up open.
func meditate(from_tile := Vector3i.ZERO, facing := Vector3i.ZERO) -> bool:
	if kind != Kind.MEDITATION:
		return _open
	if _open:
		return true
	# Meditating from a different spot replaces the streak in progress rather than extending it.
	if _streak_open and (from_tile != _streak_tile or facing != _streak_facing):
		_meditations = 0
	_streak_tile = from_tile
	_streak_facing = facing
	_streak_open = true
	_meditations += 1
	if _meditations >= meditations_required:
		_open = true
	_update_gate_label()
	_update_marker()
	return _open


## Rearming on entering a dungeon: automated gateways pick their pattern back up; locked and
## meditation ones stay open, since opening them is settled for the run.
func reset_between_visits() -> void:
	if _cycles():
		if not open_pattern.is_empty():
			_open = open_pattern[phase_offset % open_pattern.size()]
	elif kind == Kind.MEDITATION and not _open:
		_break_streak()  # leaving the dungeon breaks the streak — it has to be consecutive


## Height of the panel, in metres: above the duo's eyes, without overflowing the tile.
const GATE_HEIGHT := 0.9
## Width of the panel: nearly the whole edge, leaving a gap for the jambs.
const GATE_WIDTH := 0.9

## The text carried on EACH face of the panel, since a gateway is read from both sides: the
## opening cost for a locked one, the meditation count for a meditation one.
var _face_labels: Array[Label3D] = []


func _spawn_visual() -> void:
	var color := Color(0.55, 0.55, 0.6)  # AUTOMATED: grey
	match kind:
		Kind.LOCKED:
			color = Color(0.7, 0.6, 0.2)  # gold, for paying
		Kind.MEDITATION:
			color = Color(0.4, 0.7, 0.6)  # blue-green, for meditating
		Kind.TELEPORT:
			color = TELEPORT_COLOR
	# A thin panel sitting ON the edge: thin along the axis being crossed, wide along the other.
	# The node's origin is at the anchor tile's centre, so shift it half a tile to the edge.
	var thin := DungeonManager.EDGE_THICKNESS
	var across := Vector3(GATE_WIDTH, GATE_HEIGHT, GATE_WIDTH)
	if edge_dir.x != 0:
		across.x = thin
	else:
		across.z = thin
	var offset := Vector3(edge_dir.x, 0.0, edge_dir.z) * DungeonManager.TILE_SIZE * 0.5
	if kind == Kind.TELEPORT and not two_sided:
		# Against a wall: pulled back onto the open side, or half of it would sink into the wall.
		offset -= Vector3(edge_dir.x, 0.0, edge_dir.z) * thin * 0.5
	_add_marker_box(color, across, offset)
	if kind == Kind.LOCKED or kind == Kind.MEDITATION:
		_spawn_face_labels(offset, color)
	_update_marker()


## Writes the cost or the counter ON the panel, once per face and flush against it, rather than
## floating above: a gateway is only as tall as the duo, and text set any higher would fall out
## of view. Both faces carry the same text, because a gateway opens from either side and so has
## to read from either side, per the design doc.
func _spawn_face_labels(offset: Vector3, color: Color) -> void:
	var normal := Vector3(edge_dir.x, 0.0, edge_dir.z).normalized()
	for face in [normal, -normal]:
		var label := Label3D.new()
		label.font_size = 64
		label.pixel_size = 0.0022  # about 14 cm tall on a 90 cm panel
		label.modulate = color.lightened(0.45)
		# A price names its object ("2 x rune stone"), and without wrapping the text would run off
		# the panel. Bound it to the panel's width.
		label.width = GATE_WIDTH / label.pixel_size
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		label.no_depth_test = false
		# Flush just in front of the panel's face, at the duo's eye height: straight along the line
		# of sight, with no need to look down. The panel is tall enough to carry it.
		label.position = (
			offset
			+ face * (DungeonManager.EDGE_THICKNESS * 0.5 + 0.004)
			+ Vector3(0.0, DungeonManager.EYE_HEIGHT, 0.0)
		)
		label.rotation.y = atan2(face.x, face.z)  # a Label3D reads along its +Z
		add_child(label)
		_face_labels.append(label)
	_update_gate_label()


## Violet, and glowing while open: the one gate that never slides out of the way.
const TELEPORT_COLOR := Color(0.55, 0.3, 0.85)


## Reflects the open/closed state: closed raises the panel, open slides it flush with the
## floor. A teleport gate stays standing and lights up instead — open, it is still in the way.
func _update_marker() -> void:
	if kind != Kind.TELEPORT:
		_flatten_marker(_open)
		return
	if _marker == null:
		return
	var mat := _marker.material_override as StandardMaterial3D
	if mat == null:
		return
	mat.emission_enabled = _open
	mat.emission = TELEPORT_COLOR
	mat.emission_energy_multiplier = 1.5
	mat.albedo_color = TELEPORT_COLOR if _open else TELEPORT_COLOR.darkened(0.5)


## What a closed gateway announces about itself: its price — the design doc wants it "easily
## identified because shown on the gate itself" — or how far the meditation streak has got. Once
## open it has nothing left to say.
func _update_gate_label() -> void:
	var text := ""
	if not _open:
		match kind:
			Kind.LOCKED:
				var obj := GameData.object(cost_currency)
				var currency := tr(obj.name_key()) if obj != null else String(cost_currency)
				text = "%d × %s" % [locked_cost(), currency]
			Kind.MEDITATION:
				text = "%d/%d" % [_meditations, meditations_required]
	for label in _face_labels:
		label.text = text
