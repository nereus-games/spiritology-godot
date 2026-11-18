## Headless check on WATER, in the real "water" scenario: nobody walks into it on purpose; a fall
## ends in it (off a ledge, off a plank, by a step deflected under disarray); and whoever falls in
## comes back up on the emerge tile with the damage of the fall and nothing more.
##
## Also the rival rule (an assumption, written down in `docs/architecture.md`): rivals never go
## into water on purpose, and one made to fall in comes back up the same way, under the same
## occupancy rules.
##
## Run with: Godot --headless --path . res://scenes/dev/water_check.tscn
## As a start scene rather than --script; see geometry_check.gd.
extends Node

const ScenarioCatalog := preload("res://scripts/dev/scenario_catalog.gd")
const EXPLORATION := preload("res://scenes/exploration/exploration.tscn")
const RIVAL_SCENE := preload("res://scenes/exploration/rival/rival.tscn")
const Trap := preload("res://scripts/exploration/mechanisms/trap.gd")
const DungeonRenderer := preload("res://scripts/exploration/dungeon_renderer.gd")

## The scenario's emerge tile, its start, and a few places in it.
const EMERGE := Vector3i(1, 0, 1)
const START := Vector3i(4, 0, 0)
const SHORE := Vector3i(4, 0, 2)  # floor, with the pond straight ahead (+z)
const POND := Vector3i(4, 0, 3)
const OVER_POND := Vector3i(4, 2, 6)  # the platform's north edge, above the pond's far row
const OVER_FLOOR := Vector3i(7, 2, 6)  # ...and its east end, above plain floor
const PLANK := Vector3i(4, 0, 14)
const PENINSULA := Vector3i(1, 0, 8)  # made a floor tile with water on three sides, below

var _fails: Array[String] = []


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  OK   %s" % label)
	else:
		print("  FAIL %s" % label)
		_fails.append(label)


func _ready() -> void:
	_run_all()


func _run_all() -> void:
	await get_tree().process_frame
	_check_layout_model()
	await _check_scenario_shape()
	await _check_voluntary_step()
	await _check_ledge()
	await _check_bridge()
	await _check_disarray()
	await _check_emerge_occupied()
	await _check_emerge_mechanism()
	await _check_rivals()
	print("")
	if _fails.is_empty():
		print("ALL OK")
	else:
		print("FAILURES: %s" % [_fails])
	get_tree().quit(0 if _fails.is_empty() else 1)


# --------------------------------------------------------------------------
# Scaffolding
# --------------------------------------------------------------------------


func _setup() -> Dictionary:
	ScenarioCatalog.selected_id = &"water"
	var scene = EXPLORATION.instantiate()
	get_tree().root.add_child(scene)
	await get_tree().process_frame
	return {
		"scene": scene, "dm": scene.get_node("DungeonManager"), "player": scene.get_node("Player")
	}


func _teardown(ctx: Dictionary) -> void:
	ctx.scene.queue_free()
	await get_tree().process_frame


func _den() -> Array:
	return [
		GameSession.get_den(GameSession.PartySlot.MAIN),
		GameSession.get_den(GameSession.PartySlot.TEAMMATE)
	]


func _full() -> Array:
	return [GameSession.MAX_DEN, GameSession.MAX_DEN]


func _after_fall(levels: int) -> Array:
	var dmg := DungeonManager.fall_damage(levels)
	return [GameSession.MAX_DEN - dmg, GameSession.MAX_DEN - dmg]


## A resting rival on a tile, which therefore stays where the check puts it.
func _rival(dm, tile: Vector3i) -> Node:
	var r = RIVAL_SCENE.instantiate()
	r.species_id = &"ravbak"
	r.position = dm.tile_to_world(tile)
	dm.add_child(r)
	r.rest(99)
	return r


# --------------------------------------------------------------------------
# The model
# --------------------------------------------------------------------------


## The layout alone, in a bare dungeon: what water is, what a fall into it is, and that it is
## never walled off — while the walls of a dungeon without water come out as they always did.
func _check_layout_model() -> void:
	var dm := DungeonManager.new()
	add_child(dm)
	for x in range(0, 3):
		for z in range(0, 3):
			dm.layout.add_floor(Vector3i(x, 0, z))
	_check(dm.layout.derive_wall_tiles().size() == 12, "no water: a 3x3 room is ringed by 12 walls")
	_check(not dm.layout.has_emerge_tile(), "no emerge tile until one is declared")
	# Water where a wall would be: it is not walled, and neither does it make a wall elsewhere.
	dm.layout.mark_water(Vector3i(3, 0, 1))
	var walls: Dictionary = dm.layout.derive_wall_tiles()
	_check(
		walls.size() == 11, "a water tile on the rim is not walled off (%d walls)" % walls.size()
	)
	_check(not walls.has(Vector3i(3, 0, 1)), "...the water tile itself is not among them")
	_check(not dm.is_floor(Vector3i(3, 0, 1)), "water is not floor")
	_check(not dm.is_walkable(Vector3i(3, 0, 1)), "...so it is not walkable")
	_check(dm.layout.is_open_water(Vector3i(3, 0, 1)), "open water, with nothing to stand on")
	_check(
		dm.layout.fall_landing(Vector3i(3, 0, 1)) == Vector3i(3, 0, 1),
		"a step into water at the same level falls nowhere"
	)
	# A declared wall on the far bank of the water is drawn, though no floor touches it.
	dm.layout.declare_wall(Vector3i(4, 0, 1))
	_check(
		dm.layout.derive_wall_tiles().has(Vector3i(4, 0, 1)),
		"a declared wall on a water bank is drawn"
	)
	# A fall from a storey above ends in the water.
	_check(
		dm.layout.fall_landing(Vector3i(3, 2, 1)) == Vector3i(3, 0, 1),
		"water is where a fall from above lands"
	)
	_check(dm.layout.drops_into_water(Vector3i(3, 2, 1)), "...and a fall into it says so")
	_check(
		not dm.layout.drops_into_water(Vector3i(5, 2, 1)),
		"a fall onto nothing is no fall into water"
	)
	_check(not dm.layout.drops_into_water(Vector3i(1, 2, 1)), "...nor is a fall onto floor")
	# A plank over water: floor and water at once, a fall of height 0.
	var plank := Vector3i(3, 0, 1)
	dm.layout.add_floor(plank)
	dm.layout.mark_pit(plank)
	_check(
		dm.layout.plank_over_water(plank), "a floor tile that is water too is a plank over water"
	)
	_check(
		dm.layout.has_drop(plank) and dm.layout.drops_into_water(plank),
		"a fall off it ends in the water"
	)
	_check(dm.layout.fall_end(plank) == plank, "...at height 0, on its own tile")
	# A plank over a drop with water further down.
	var high := Vector3i(3, 3, 1)
	dm.layout.add_floor(high)
	_check(
		dm.layout.fall_end(high) == plank,
		"a plank high up falls to the plank at water level, not through it"
	)
	dm.layout.remove_floor(plank)
	_check(
		dm.layout.fall_end(high) == Vector3i(3, 0, 1),
		"...or to the water itself, when no plank lies on it"
	)
	_check(dm.layout.drops_into_water(high), "...and that is a fall into water")
	dm.layout.set_emerge_tile(Vector3i(1, 0, 1))
	_check(
		dm.layout.has_emerge_tile() and dm.layout.emerge_tile() == Vector3i(1, 0, 1),
		"the emerge tile is declared"
	)
	_check(
		dm.emerge_destination(Vector3i(0, 0, 0)) == Vector3i(1, 0, 1),
		"...and whoever falls in comes back up on it"
	)
	dm.free()


func _check_scenario_shape() -> void:
	var ctx := await _setup()
	var dm = ctx.dm
	_check(
		dm.layout.has_emerge_tile() and dm.layout.emerge_tile() == EMERGE,
		"the scenario declares its emerge tile"
	)
	_check(dm.is_floor(EMERGE), "...on floor")
	_check(dm.layout.is_water(POND) and not dm.is_floor(POND), "the pond is water")
	_check(
		dm.layout.water_tiles().size() == 12 + 27,
		"the pond (12) and the channel (27, planks included)"
	)
	var walled := 0
	for w in dm.layout.derive_wall_tiles():
		if dm.layout.is_water(w):
			walled += 1
	_check(walled == 0, "no water tile is walled off")
	_check(dm.layout.plank_over_water(PLANK), "the plank lies over the channel")
	# The surface is drawn: one slab of the water colour per tile, with the plank still there.
	var slabs := 0
	var off_level := 0
	for child in dm.get_children():
		var mi := child as MeshInstance3D
		if mi == null or mi.material_override == null:
			continue
		var mat := mi.material_override as StandardMaterial3D
		if mat != null and mat.albedo_color == DungeonRenderer.WATER_COLOR:
			slabs += 1
			var top: float = mi.position.y + mi.mesh.size.y * 0.5 + dm.WATER_SURFACE_DROP
			if absf(top - roundf(top)) > 0.001:
				off_level += 1
	_check(
		slabs == dm.layout.water_tiles().size(),
		"%d water slabs drawn for %d water tiles" % [slabs, dm.layout.water_tiles().size()]
	)
	_check(off_level == 0, "every water surface lies just under its tile's floor level")
	var planks := 0
	for child in dm.get_children():
		var mi := child as MeshInstance3D
		if mi != null and mi.mesh is BoxMesh and is_equal_approx(mi.mesh.size.y, 0.1):
			var mat := mi.material_override as StandardMaterial3D
			if mat != null and mat.albedo_color == Color(0.52, 0.38, 0.24):
				planks += 1
	_check(planks == 3, "the three planks over the water are drawn")
	await _teardown(ctx)


# --------------------------------------------------------------------------
# Falling in
# --------------------------------------------------------------------------


## A chosen step into water at the same level is blocked like a wall: no fall, no damage, no turn
## — even with floor further down, which a plain step into empty space would fall to.
func _check_voluntary_step() -> void:
	var ctx := await _setup()
	var dm = ctx.dm
	var player = ctx.player
	dm.layout.add_floor(Vector3i(POND.x, -1, POND.z))  # an underground below the pond
	player.teleport_to(SHORE)
	var turns: int = dm.turn_count
	await player.try_move(Vector3.FORWARD)
	_check(player.tile == SHORE, "a step into water leaves the player where they were")
	_check(_den() == _full(), "...with no damage")
	_check(dm.turn_count == turns, "...and no turn spent, like a wall")
	_check(player.is_at_rest(), "...nothing is left animating")
	await _teardown(ctx)


## A step off the unrailed platform: 2 storeys, 10 DEN each, and the water hands the duo back on
## the emerge tile. Beside it, the same step over plain floor ends on that floor.
func _check_ledge() -> void:
	var ctx := await _setup()
	var dm = ctx.dm
	var player = ctx.player
	_check(
		dm.layout.drops_into_water(OVER_POND + Vector3i(0, 0, -1)),
		"the platform's north edge overhangs the pond"
	)
	player.teleport_to(OVER_POND)
	var turns: int = dm.turn_count
	await player.try_move(Vector3.BACK)  # north
	_check(
		player.tile == EMERGE,
		"off the ledge into the pond: back up on the emerge tile (%s)" % player.tile
	)
	_check(
		_den() == _after_fall(2),
		"...with the damage of a 2-storey fall and nothing more (%s)" % [_den()]
	)
	_check(dm.turn_count == turns + 1, "...and the fall costs one turn")
	_check(player.is_at_rest(), "...and ends at rest")
	await _teardown(ctx)

	ctx = await _setup()
	dm = ctx.dm
	player = ctx.player
	player.teleport_to(OVER_FLOOR)
	await player.try_move(Vector3.BACK)
	_check(
		player.tile == Vector3i(7, 0, 5),
		"off the east end: onto the floor below, no emerging (%s)" % player.tile
	)
	_check(_den() == _after_fall(2), "...for the same 10 DEN")
	await _teardown(ctx)


## A fall off the plank over the channel: height 0, so no damage, and the emerge tile.
func _check_bridge() -> void:
	var ctx := await _setup()
	var dm = ctx.dm
	var player = ctx.player
	var scene = ctx.scene
	player.teleport_to(PLANK)
	scene._bridge_from = PLANK
	var turns: int = dm.turn_count
	await scene._fall_off_bridge(player)
	_check(
		player.tile == EMERGE,
		"off the plank into the channel: back up on the emerge tile (%s)" % player.tile
	)
	_check(_den() == _full(), "...a plank at the water's level costs nothing (%s)" % [_den()])
	_check(dm.turn_count == turns + 1, "...and the fall costs one turn")
	_check(not player.input_locked, "...and the controls are free again")
	await _teardown(ctx)

	# A plank high above the water falls the full height.
	ctx = await _setup()
	dm = ctx.dm
	player = ctx.player
	scene = ctx.scene
	var high := Vector3i(4, 2, 14)
	dm.layout.add_floor(high)
	dm.layout.mark_pit(high)
	_check(
		dm.layout.has_drop(high) and dm.layout.fall_end(high) == PLANK,
		"a plank two storeys up falls onto the lower plank"
	)
	dm.layout.remove_floor(PLANK)  # nothing but the water below
	player.teleport_to(high)
	scene._bridge_from = high
	await scene._fall_off_bridge(player)
	_check(player.tile == EMERGE, "off a plank over the water from two storeys up: the emerge tile")
	_check(_den() == _after_fall(2), "...with the 10 DEN of a 2-storey fall (%s)" % [_den()])
	await _teardown(ctx)


## A step deflected into water under disarray falls in, at height 0. A peninsula with water on
## all three other sides makes every possible deflection a plunge; the underground below it is what
## a step into empty space would fall to.
func _check_disarray() -> void:
	var ctx := await _setup()
	var dm = ctx.dm
	var player = ctx.player
	for t in [Vector3i(0, 0, 8), Vector3i(2, 0, 8), Vector3i(1, 0, 7)]:
		dm.layout.remove_floor(t)
		dm.layout.mark_water(t)
		dm.layout.add_floor(Vector3i(t.x, -1, t.z))
	player.teleport_to(PENINSULA)
	var aff = player.affliction
	aff.add_disarray(30)
	while aff.has_disarray() and not aff.peek_move():
		aff.consume_move()
	_check(aff.peek_move(), "the next move is deflected")
	var turns: int = dm.turn_count
	await player.try_move(Vector3.FORWARD)  # towards the floor; deflected into water
	_check(
		player.tile == EMERGE,
		"a deflected step into water: back up on the emerge tile (%s)" % player.tile
	)
	_check(_den() == _full(), "...a fall of height 0 costs nothing (%s)" % [_den()])
	_check(dm.turn_count == turns + 1, "...and the step costs one turn")
	# The same step, not deflected, is the usual wall.
	while aff.has_disarray():
		aff.consume_move()
	player.teleport_to(PENINSULA)
	await player.try_move(Vector3.BACK)
	_check(player.tile == PENINSULA, "undeflected, the same step into water is blocked")
	await _teardown(ctx)


# --------------------------------------------------------------------------
# The emerge tile
# --------------------------------------------------------------------------


## Somebody on the emerge tile: whoever falls in comes back up on the nearest free tile instead.
func _check_emerge_occupied() -> void:
	var ctx := await _setup()
	var dm = ctx.dm
	var player = ctx.player
	var squatter = _rival(dm, EMERGE)
	_check(dm.occupant_at(EMERGE) == squatter, "a rival stands on the emerge tile")
	player.teleport_to(OVER_POND)
	await player.try_move(Vector3.BACK)
	var gap: Vector3i = player.tile - EMERGE
	_check(player.tile != EMERGE, "the player does not come up on top of it (%s)" % player.tile)
	_check(
		dm.is_floor(player.tile) and absi(gap.x) + absi(gap.y) + absi(gap.z) == 1,
		"...but on a free tile next to it"
	)
	_check(dm.occupant_at(EMERGE) == squatter, "...and nobody was evicted")
	await _teardown(ctx)


## The emerge tile's mechanisms fire on arrival, like on any tile the player reaches.
func _check_emerge_mechanism() -> void:
	var ctx := await _setup()
	var dm = ctx.dm
	var player = ctx.player
	ScenarioCatalog.place(dm, Trap, EMERGE, {"kind": Trap.Kind.POISON, "revealed": true})
	player.teleport_to(OVER_POND)
	var before: int = player.affliction.poison_turns
	await player.try_move(Vector3.BACK)
	_check(player.tile == EMERGE, "back up on the emerge tile, with a trap on it")
	_check(player.affliction.poison_turns > before, "...which springs on arrival")
	await _teardown(ctx)


# --------------------------------------------------------------------------
# Rivals: never into water on purpose; if made to fall in, they come back up the same way
# --------------------------------------------------------------------------


func _check_rivals() -> void:
	var ctx := await _setup()
	var dm = ctx.dm
	# On the platform, a rival chasing a target on the ground below does not jump into the pond,
	# though that is the open edge nearest to the target.
	var edge := Vector3i(4, 2, 6)
	var jumper = _rival(dm, edge)
	var brink: Vector3i = jumper._open_drop_edge(Vector3i(4, 0, 5))
	_check(brink == edge, "a rival does not pick an edge over water to jump from (%s)" % brink)
	# ...while the east end, over plain floor, is still a way down for it.
	jumper.queue_free()
	await get_tree().process_frame
	var east = _rival(dm, OVER_FLOOR)
	_check(
		east._open_drop_edge(Vector3i(7, 0, 5)) == OVER_FLOOR + Vector3i(0, 0, -1),
		"...but jumps over plain floor as before"
	)
	east.queue_free()
	await get_tree().process_frame
	# A rival never steps into water on foot.
	var walker = _rival(dm, SHORE)
	_check(not dm.can_step(SHORE, POND), "a rival has no step into water")
	_check(not dm.move_occupant(SHORE, POND, walker), "...and cannot be moved there")
	_check(dm.occupant_at(SHORE) == walker, "...so it stays on its tile")
	walker.queue_free()
	await get_tree().process_frame

	# Made to fall in — here by being pushed off the ledge — it comes back up on the emerge tile,
	# with the damage of the fall.
	var faller = _rival(dm, OVER_POND)
	var before: int = faller.den
	var alive: bool = faller.fall_down(OVER_POND + Vector3i(0, 0, -1))
	_check(alive, "a rival falling into water survives the 2-storey fall")
	_check(faller.tile == EMERGE, "...and comes back up on the emerge tile (%s)" % faller.tile)
	_check(
		faller.den == before - DungeonManager.fall_damage(2),
		"...with the fall's damage and no more (%d -> %d)" % [before, faller.den]
	)
	_check(dm.occupant_at(EMERGE) == faller, "...and holds the tile")
	# A second one: the emerge tile is taken, so it takes the nearest free one.
	var second = _rival(dm, OVER_POND + Vector3i(1, 0, 0))
	second.fall_down(OVER_POND + Vector3i(1, 0, -1))
	_check(
		second.tile != EMERGE and dm.is_floor(second.tile),
		"a second rival comes up on a free tile (%s)" % second.tile
	)
	_check(
		dm.occupant_at(EMERGE) == faller and dm.occupant_at(second.tile) == second,
		"...one occupant per tile"
	)
	# Two rivals meeting on the plank over the channel both fall, and both come back up apart.
	var a = _rival(dm, Vector3i(4, 0, 12))
	var b = _rival(dm, PLANK)
	a._collide_with_rival(PLANK, b)
	_check(
		a.tile != b.tile and dm.is_floor(a.tile) and dm.is_floor(b.tile),
		"two rivals meeting on a plank over water come up apart"
	)
	_check(a.den == a.max_den and b.den == b.max_den, "...at height 0, so unharmed")
	await _teardown(ctx)
