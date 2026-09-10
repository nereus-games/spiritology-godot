## Catalogue of dev TEST scenarios: each one populates a [DungeonManager] with a subset of
## mechanisms, so one element can be tested at a time without standing the whole thing up.
##
## Two halves, split on purpose: the TEXTS (title, instructions) are [ScenarioData] in
## `data/scenarios/`, editable without touching code; BUILDING the dungeon is the code below,
## one builder per scenario. The `id` ties the two together, and `data_integrity_check` verifies
## that neither side points at nothing.
##
## `selected_id` is set by the selection screen and read by `exploration.gd`, which calls
## [method build] and places the player on the cell it returns. The HUD's MENU button goes back
## to the selection screen, for now.
##
## No `class_name` (the CLI class-cache trap): referenced by `preload`. References the autoloads
## and the mechanism scripts, which is fine in game since it loads after boot.
extends RefCounted

const Trap := preload("res://scripts/exploration/mechanisms/trap.gd")
const Gateway := preload("res://scripts/exploration/mechanisms/gateway.gd")
const CrumblyGround := preload("res://scripts/exploration/mechanisms/crumbly_ground.gd")
const Litter := preload("res://scripts/exploration/mechanisms/litter.gd")
const Chest := preload("res://scripts/exploration/mechanisms/chest.gd")
const RefreshCrystal := preload("res://scripts/exploration/mechanisms/refresh_crystal.gd")
const Dieverting := preload("res://scripts/exploration/mechanisms/dieverting.gd")
const CrackedWall := preload("res://scripts/exploration/mechanisms/cracked_wall.gd")
const ExaminableDecor := preload("res://scripts/exploration/mechanisms/examinable_decor.gd")
const NarrowBridge := preload("res://scripts/exploration/mechanisms/narrow_bridge.gd")
const Stairs := preload("res://scripts/exploration/mechanisms/stairs.gd")
const Elevator := preload("res://scripts/exploration/mechanisms/elevator.gd")
const Guardrail := preload("res://scripts/exploration/mechanisms/guardrail.gd")
const AbilityCatalog := preload(
	"res://scripts/exploration/abilities/exploration_ability_catalog.gd"
)
const RIVAL_SCENE := preload("res://scenes/exploration/rival/rival.tscn")

## The scenario picked on the selection screen; the first one by default.
static var selected_id: StringName = &"movement"

## The species the mini personality quiz can give the MAIN CHARACTER (the design doc's
## "Introduction / Mini Personality Quiz", Available Results).
const MAIN_SPECIES: Array[StringName] = [&"ravbak", &"akturlin", &"erzelak", &"zuk"]

## The species the quiz can give the TEAMMATE: the same as the main character's, plus six more
## (same section). The duo can carry the same species twice.
const TEAMMATE_SPECIES: Array[StringName] = [
	&"ravbak",
	&"akturlin",
	&"erzelak",
	&"zuk",
	&"razel",
	&"jezal",
	&"gelmi",
	&"granop",
	&"fopin",
	&"spodra",
]

## DEV: the duo forced on the scenarios, picked on the selection screen. In the real game the
## personality quiz assigns it; here it is chosen by hand, staying within the results the quiz
## can give each of the two roles.
static var main_species: StringName = &"ravbak"
static var teammate_species: StringName = &"razel"

## DEV: the maximum DEN forced on the scenarios' rivals, set with a slider on the selection
## screen. A rival's DEN is normally a LEVEL DESIGN knob, per dungeon; this slider exists to try
## values by hand. 0 keeps the rival's own default.
static var rival_den_override := 0

const SCENARIO_DIR := "res://data/scenarios/"

## The scenario records, in the selection screen's order. The directory is read alphabetically,
## so [member ScenarioData.order] is what sets the intended progression.
static var _list: Array = []


static func list() -> Array:
	if not _list.is_empty():
		return _list
	var dir := DirAccess.open(SCENARIO_DIR)
	if dir == null:
		push_error("[ScenarioCatalog] directory not found: %s" % SCENARIO_DIR)
		return _list
	for f in dir.get_files():
		if f.ends_with(".tres"):
			var res := load(SCENARIO_DIR + f) as ScenarioData
			if res != null:
				_list.append(res)
	_list.sort_custom(func(a, b): return a.order < b.order)
	return _list


static func title_for(id: StringName) -> String:
	for s in list():
		if s.id == id:
			return s.title
	return String(id)


## Builds the scenario into `dm` and returns the player's starting cell.
static func build(id: StringName, dm) -> Vector3i:
	_reset_session()
	match id:
		&"movement":
			return _movement(dm)
		&"traps":
			return _traps(dm)
		&"gates":
			return _gates(dm)
		&"grounds":
			return _grounds(dm)
		&"chests":
			return _chests(dm)
		&"walls":
			return _walls(dm)
		&"bridge":
			return _bridge(dm)
		&"bridge_rival":
			return _bridge_rival(dm)
		&"stairs":
			return _stairs(dm)
		&"abilities":
			return _abilities(dm)
	# Silently falling back to another scenario made an unknown id look like it "worked" for a
	# while. Something is still built, so the game does not crash, but it is said out loud — and
	# the checks fail on a reported error.
	push_error("[ScenarioCatalog] scenario with no builder: %s" % id)
	return _traps(dm)


# --------------------------------------------------------------------------
# Building helpers
# --------------------------------------------------------------------------


static func _reset_session() -> void:
	GameSession.inventory.clear()
	GameSession.used_exploration_abilities.clear()
	AbilityCatalog.dev_granted = []
	GameSession.set_den(GameSession.PartySlot.MAIN, GameSession.MAX_DEN)
	GameSession.set_den(GameSession.PartySlot.TEAMMATE, GameSession.MAX_DEN)
	GameSession.restore_party_eth()
	GameSession.main_character = main_species
	GameSession.teammate = teammate_species


static func _floor_rect(dm, x0: int, z0: int, w: int, d: int) -> void:
	for x in range(x0, x0 + w):
		for z in range(z0, z0 + d):
			dm.add_floor(Vector3i(x, 0, z))


static func _floor_line(dm, x: int, z0: int, length: int) -> void:
	for z in range(z0, z0 + length):
		dm.add_floor(Vector3i(x, 0, z))


## A rectangular floor at a given STOREY (y).
static func _floor_rect_y(dm, x0: int, z0: int, w: int, d: int, y: int) -> void:
	for x in range(x0, x0 + w):
		for z in range(z0, z0 + d):
			dm.add_floor(Vector3i(x, y, z))


## Instantiates a mechanism, applies `props`, puts it on `cell` and adds it to the dungeon.
static func _place(dm, script, cell: Vector3i, props: Dictionary = {}) -> Node:
	var m = script.new()
	for k in props:
		m.set(k, props[k])
	m.position = dm.cell_to_world(cell)
	dm.add_child(m)
	return m


static func _spawn_rival(dm, species: StringName, cell: Vector3i) -> Node:
	var r = RIVAL_SCENE.instantiate()
	r.species_id = species
	if rival_den_override > 0:
		r.max_den = rival_den_override  # set BEFORE entering the tree, since _ready reads it
	r.position = dm.cell_to_world(cell)
	dm.add_child(r)
	return r


# --------------------------------------------------------------------------
# Scenarios
# --------------------------------------------------------------------------


static func _movement(dm) -> Vector3i:
	# An empty room with a few pillars to navigate around; removing cells renders them as walls.
	_floor_rect(dm, 0, 0, 7, 9)
	for pillar in [
		Vector3i(2, 0, 3),
		Vector3i(4, 0, 3),
		Vector3i(3, 0, 6),
		Vector3i(1, 0, 6),
		Vector3i(5, 0, 6)
	]:
		dm._floor.erase(pillar)
	return Vector3i(3, 0, 0)


static func _traps(dm) -> Vector3i:
	_floor_rect(dm, 0, 0, 3, 9)
	_place(dm, Trap, Vector3i(1, 0, 2), {"kind": Trap.Kind.POISON, "revealed": true})
	_place(dm, Trap, Vector3i(1, 0, 4), {"kind": Trap.Kind.TELEPORT, "revealed": true})
	_place(dm, Trap, Vector3i(1, 0, 6), {"kind": Trap.Kind.DISARRAY, "revealed": true})
	return Vector3i(1, 0, 0)


static func _gates(dm) -> Vector3i:
	_floor_line(dm, 1, 0, 11)  # a one-cell corridor, so the gateways genuinely block
	# The gateways sit on the EDGE between the anchor cell and the next one (+z), so both cells
	# stay walkable and you can wait right in front.
	var gate_edge := Vector3i(0, 0, 1)
	_place(dm, Gateway, Vector3i(1, 0, 3), {"kind": Gateway.Kind.AUTOMATED, "edge_dir": gate_edge})
	# THIS gateway's currency, a level-design choice: the design doc's "spades OR rune stones" is
	# the author's pick, not an alternative offered to the player.
	_place(
		dm,
		Gateway,
		Vector3i(1, 0, 6),
		{
			"kind": Gateway.Kind.LOCKED,
			"cost_tier": Gateway.CostTier.EARLY,
			"cost_currency": &"spade",
			"edge_dir": gate_edge
		}
	)
	_place(dm, Gateway, Vector3i(1, 0, 9), {"kind": Gateway.Kind.MEDITATION, "edge_dir": gate_edge})
	# A heap BEHIND the meditation gateway: while it is closed the gateway hides the heap, so its
	# examine and recycle actions are not offered. They appear once it opens.
	_place(dm, Litter, Vector3i(1, 0, 10))
	GameSession.add_object(&"spade", 2)  # enough to open the locked gateway
	return Vector3i(1, 0, 0)


static func _grounds(dm) -> Vector3i:
	_floor_rect(dm, 0, 0, 3, 5)
	_place(dm, CrumblyGround, Vector3i(1, 0, 1))
	_place(dm, Litter, Vector3i(1, 0, 3))
	GameSession.add_object(&"spade", 1)  # for Dig
	AbilityCatalog.dev_granted = [&"fog_mantel"]  # an ability for Recycle to refresh
	GameSession.mark_exploration_ability_used(&"fog_mantel")
	return Vector3i(1, 0, 0)


static func _chests(dm) -> Vector3i:
	_floor_rect(dm, 0, 0, 3, 9)
	_place(dm, Chest, Vector3i(1, 0, 1))  # loot
	# A disguised teleport trap. With razél in the duo, and so the Reveal Traps talent, it offers
	# the teleport-or-stay choice instead of teleporting outright.
	_place(dm, Chest, Vector3i(1, 0, 3), {"is_trap": true})
	_place(dm, RefreshCrystal, Vector3i(0, 0, 2))  # an obstacle, refreshable from adjacent
	# Two dice: on the first the player can choose, holding a spade; the second goes off on its
	# own, the spade having been spent or lost to the outcome rolled.
	_place(dm, Dieverting, Vector3i(1, 0, 5))
	_place(dm, Dieverting, Vector3i(1, 0, 7))
	GameSession.add_object(&"spade", 1)  # enough to destroy ONE die
	# An exit at the end of the corridor, to tell "sent back to the entrance" apart from "sent to
	# an exit". The entrance itself is declared by `exploration.gd` on the starting cell.
	dm.add_exit(Vector3i(1, 0, 8))
	AbilityCatalog.dev_granted = [&"fog_mantel"]  # so the crystal has something to refresh
	GameSession.mark_exploration_ability_used(&"fog_mantel")
	return Vector3i(1, 0, 0)


static func _walls(dm) -> Vector3i:
	# Two areas split by a row of walls at z=3, pierced by a cracked wall at (1,0,3).
	_floor_rect(dm, 0, 0, 3, 3)  # z 0..2
	_floor_rect(dm, 0, 4, 3, 3)  # z 4..6
	_place(dm, CrackedWall, Vector3i(1, 0, 3))
	_place(
		dm, ExaminableDecor, Vector3i(0, 0, 1), {"decor_type": ExaminableDecor.DecorType.POSTERS}
	)
	AbilityCatalog.dev_granted = [&"cranny_crossing"]
	return Vector3i(1, 0, 0)


## The same ravine as [method _bridge], plus a rival that follows you onto the plank. Exercises
## the design doc's rival rules: the simplified balance test, meeting means both fall, and
## chasing through a fall.
static func _bridge_rival(dm) -> Vector3i:
	# No disarray trap: what is being exercised here is the rival rules, not command inertia.
	var start := _build_bridge_map(dm, false)
	# The rival is placed on the FAR SIDE of the ravine, so it has to take the bridge to reach
	# you and the encounter necessarily happens ON a plank. Placed on the starting side it caught
	# you before you even set off, and all that got tested was ordinary contact.
	_spawn_rival(dm, &"ravbak", Vector3i(1, 2, 7))
	return start


static func _bridge(dm) -> Vector3i:
	return _build_bridge_map(dm)


## Geometry shared by both bridge scenarios. `disarray_trap` decides whether the trap on the
## far cell is placed: useful to test the return trip under disarray, noise when testing rivals.
static func _build_bridge_map(dm, disarray_trap: bool = true) -> Vector3i:
	# A ravine TWO storeys deep, spanned by a narrow log. Falling off the bridge is not a "back to
	# the start": you land at the BOTTOM, taking normal fall damage proportional to the depth, and
	# climb back up two flights of stairs on the x = 3 side.
	#
	#   y = 2  platforms + bridge     y = 1  return ledge     y = 0  floor of the ravine
	_floor_rect_y(dm, 0, 0, 3, 2, 2)  # starting platform, x 0..2, z 0..1
	dm.add_floor(Vector3i(3, 2, 0))  # top landing of the second flight
	dm.add_floor(Vector3i(1, 2, 7))  # arrival: ONE cell, walled on 3 sides by render_grid
	# (the bridge is the only way out, so the return trip
	# starts on it without wasting disarray moves)
	# The bridge: every cell carries the mechanism, engaged along whichever way you face. Walkable
	# but marked a pit — only the plank holds it up, and the ravine opens below.
	for z in range(2, 7):
		var c := Vector3i(1, 2, z)
		dm.add_floor(c)
		dm.mark_pit(c)
		_spawn_plank(dm, c)
		_place(dm, NarrowBridge, c)
	# Floor of the ravine, 2 storeys down, catching a fall along the whole length of the bridge.
	_floor_rect_y(dm, 0, 2, 4, 5, 0)  # x 0..3, z 2..6
	dm._floor.erase(Vector3i(3, 0, 4))  # the first flight's shaft: you never land ON the stairs
	# The intermediate ledge linking the two flights.
	dm.add_floor(Vector3i(3, 1, 2))
	dm.add_floor(Vector3i(3, 1, 3))
	# The climb back: floor to ledge, then ledge to the STARTING platform — falling does not win
	# you the crossing. Each flight is one upward cell plus its downward cell above it.
	_place(dm, Stairs, Vector3i(3, 0, 4), {"level_delta": 1, "face_dir": Vector3i(0, 0, -1)})
	_place(dm, Stairs, Vector3i(3, 1, 4), {"level_delta": -1, "face_dir": Vector3i(0, 0, 1)})
	_place(dm, Stairs, Vector3i(3, 1, 1), {"level_delta": 1, "face_dir": Vector3i(0, 0, -1)})
	_place(dm, Stairs, Vector3i(3, 2, 1), {"level_delta": -1, "face_dir": Vector3i(0, 0, 1)})
	# A disarray trap on the ARRIVAL cell: it springs by itself as you step off the bridge, so the
	# outward trip is tested in the normal state and the return under disarray (+25% command
	# inertia). The duration is raised to 6-8 moves for THIS test, against the design doc's 3-5:
	# turning around already costs 2 moves and stepping onto the plank a third, so at 3-5 the
	# return crossing would be a coin flip on whether any disarray was left. At 6-8 there are 3-5
	# left for the bridge, which counts them down cell by cell — you watch the HUD counter drop as
	# you cross.
	if disarray_trap:
		_place(
			dm,
			Trap,
			Vector3i(1, 2, 7),
			{"kind": Trap.Kind.DISARRAY, "revealed": true, "disarray_min": 6, "disarray_max": 8}
		)
	return Vector3i(1, 2, 0)


## A bridge plank: a narrow brown box along the direction of travel, its top face level with the
## cell's floor — which the pit marking left empty.
static func _spawn_plank(dm, cell: Vector3i) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.35, 0.1, dm.CELL_SIZE)
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.52, 0.38, 0.24)
	mi.material_override = mat
	mi.position = dm.cell_to_world(cell) + Vector3(0.0, -0.05, 0.0)
	dm.add_child(mi)


static func _stairs(dm) -> Vector3i:
	# A FIVE-tier pyramid, to exercise the design doc's whole fall scale (1 unit = 0 damage,
	# 2 = 10, 3 = 15, 4 = 20) and both shapes of elevator.
	#
	#   storey 0: x 0..7, z 0..12      (the access hall, running UNDER every tier)
	#   storey 1: x 1..6, z 4..12
	#   storey 2: x 2..6, z 4..12
	#   storey 3: x 3..6, z 4..12
	#   storey 4: x 4..6, z 4..12
	#
	# The EAST column (x = 7): nothing stops a fall before storey 0, so stepping off tier 1/2/3/4
	# costs 1/2/3/4 units, that is 0/10/15/20 DEN. On the WEST side each tier overhangs the next,
	# a single unit, and so is painless.
	_floor_rect_y(dm, 0, 0, 8, 13, 0)
	_floor_rect_y(dm, 1, 4, 6, 9, 1)
	_floor_rect_y(dm, 2, 4, 5, 9, 2)
	_floor_rect_y(dm, 3, 4, 4, 9, 3)
	_floor_rect_y(dm, 4, 4, 3, 9, 4)

	# A PILLAR: one cell of storey 0 is removed under tier 1, so it becomes a wall block and ITS
	# top face serves as the floor of the cell above (the design doc's "Walls + Decors": a wall can
	# serve as ground on the floor above it, which avoids stacking wall plus slab).
	dm._floor.erase(Vector3i(1, 0, 8))

	# GUARDRAILS: the top tier's east edge is protected only along its first two cells. Two steps
	# further the same edge is open, and costs a 4-unit fall — the two are a step apart, so they
	# can be compared directly.
	for z in [4, 5]:
		_place(dm, Guardrail, Vector3i(6, 4, z), {"edge_dir": Vector3i(1, 0, 0)})

	# ONE STAIRCASE PER TIER, staggered towards +z. This is the always-usable route: an elevator
	# stays where it was left — the design doc has you step back on to call it — so without these
	# flights, falling off a storey served only by the elevator would make the top permanently
	# unreachable.
	for flight in [Vector3i(1, 0, 4), Vector3i(2, 1, 6), Vector3i(3, 2, 8), Vector3i(4, 3, 10)]:
		var up: Vector3i = flight
		var down: Vector3i = up + Vector3i(0, 1, 0)
		dm._floor.erase(up)  # a flight's cell is not walkable: you are carried past it
		dm._floor.erase(down)
		_place(dm, Stairs, up, {"level_delta": 1, "face_dir": Vector3i(0, 0, 1)})
		_place(dm, Stairs, down, {"level_delta": -1, "face_dir": Vector3i(0, 0, -1)})

	# The elevators are SHORTCUTS, doubled by the staircases above.
	# `path` is a TYPED Array[Vector3i]: passing an untyped Array through `set()` would fail
	# silently, and the mechanism would end up with no path at all.
	# 1 <-> 2: a plain VERTICAL trip, one waypoint.
	var straight: Array[Vector3i] = [Vector3i(6, 2, 12)]
	_place(dm, Elevator, Vector3i(6, 1, 12), {"path": straight})
	# 3 <-> 4: a COMPLEX trip that swings out over empty space and chains segments along all three
	# axes (+x, +z, +y, -x) before settling on the top tier.
	var winding: Array[Vector3i] = [
		Vector3i(7, 3, 5), Vector3i(7, 3, 12), Vector3i(7, 4, 12), Vector3i(6, 4, 12)
	]
	_place(dm, Elevator, Vector3i(6, 3, 5), {"path": winding})
	return Vector3i(3, 0, 0)


static func _abilities(dm) -> Vector3i:
	_floor_rect(dm, 0, 0, 3, 10)
	# Granted abilities plus exploration objects in the inventory.
	AbilityCatalog.dev_granted = [&"fog_mantel", &"static_camouflage"]
	GameSession.add_object(&"tea_drop", 1)
	GameSession.add_object(&"rune_stone", 2)
	GameSession.add_object(&"torment_veil", 1)
	GameSession.add_object(&"smoke_bomb", 1)  # must stay unavailable during exploration
	# A poison trap to test tea_drop, and a chasing rival to test fog mantel and torment veil.
	_place(dm, Trap, Vector3i(1, 0, 2), {"kind": Trap.Kind.POISON, "revealed": true})
	_spawn_rival(dm, &"ravbak", Vector3i(1, 0, 8))
	return Vector3i(1, 0, 0)
