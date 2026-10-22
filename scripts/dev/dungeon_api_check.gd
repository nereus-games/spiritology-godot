## Headless check of the dungeon model's public API in a BARE dungeon — floor, holes and pits,
## derived walls, entrance and exits, the tile searches and teleporting. It exists to pin the
## behaviour of what `DungeonManager` hands out, so that moving a block of it to a collaborator
## cannot change it unnoticed. The scenario checks cover these paths only in passing.
##
## Run with: Godot --headless --path . res://scenes/dev/dungeon_api_check.tscn
## As a start scene rather than --script; see geometry_check.gd.
extends Node

const Fixture := preload("res://scripts/dev/dungeon_api_fixture.gd")

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
	_check_floor()
	_check_holes_and_pits()
	await _check_derived_walls()
	_check_entrance_and_exits()
	_check_free_tiles()
	_check_walking_distances()
	_check_random_floor_tile()
	_check_teleporting()
	print("")
	if _fails.is_empty():
		print("ALL OK")
	else:
		print("FAILURES: %s" % [_fails])
	get_tree().quit(0 if _fails.is_empty() else 1)


## A bare dungeon with a `width` x `depth` floor at level 0, no player, nothing else.
func _field(width: int, depth: int):
	return Fixture.field(self, width, depth)


func _check_floor() -> void:
	print("[floor]")
	var dm = _field(3, 3)
	_check(dm.is_floor(Vector3i(1, 0, 1)), "a laid tile is floor")
	_check(not dm.is_floor(Vector3i(3, 0, 0)), "a tile outside is not")
	_check(dm.floor_tiles().size() == 9, "the floor holds nine tiles")
	dm.set_floor_tiles([Vector3i(5, 0, 5)])
	_check(
		dm.floor_tiles().size() == 1 and dm.is_floor(Vector3i(5, 0, 5)), "set replaces the floor"
	)
	_check(not dm.is_floor(Vector3i(1, 0, 1)), "...and drops the old tiles")
	dm.queue_free()


func _check_holes_and_pits() -> void:
	print("[holes and pits]")
	var dm = _field(3, 3)
	var far := Vector3i(8, 0, 8)
	_check(not dm.is_hole(far) and not dm.is_bottomless(far), "an ordinary tile is no hole")
	dm.mark_hole(far)
	_check(dm.is_hole(far), "a marked hole is a hole")
	_check(dm.is_bottomless(far), "a hole with nothing below it is bottomless")
	_check(dm.fall_landing(far) == far, "...and its fall lands nowhere")
	dm.add_floor(Vector3i(8, -2, 8))
	_check(dm.fall_landing(far) == Vector3i(8, -2, 8), "a floor below catches the fall")
	_check(not dm.is_bottomless(far), "...so the hole is no longer bottomless")
	_check(dm.fall_landing(Vector3i(8, 5, 8)) == Vector3i(8, -2, 8), "a fall passes through air")
	_check(dm.fall_landing(Vector3i(8, 30, 8)) == Vector3i(8, 30, 8), "a fall has a limited reach")
	dm.add_floor(far)
	_check(not dm.is_bottomless(far), "a hole with floor on it is not bottomless")
	var pit := Vector3i(1, 0, 1)
	_check(dm.pit_tiles().is_empty(), "no pit until one is marked")
	dm.mark_pit(pit)
	_check(dm.pit_tiles().has(pit) and dm.pit_tiles().size() == 1, "a marked pit is listed")
	dm.queue_free()


func _check_derived_walls() -> void:
	print("[derived walls]")
	var dm = _field(2, 2)
	var walls: Dictionary = dm.derive_wall_tiles()
	_check(walls.size() == 8, "a 2x2 room is walled by its eight orthogonal neighbours")
	_check(walls.has(Vector3i(-1, 0, 0)) and walls.has(Vector3i(2, 0, 1)), "...on every side")
	_check(not walls.has(Vector3i(-1, 0, -1)), "...but not on its corners")
	_check(dm.wall_tiles().is_empty() and not dm.is_wall(Vector3i(-1, 0, 0)), "none before render")
	dm.render_grid()
	_check(dm.wall_tiles().size() == 8, "render_grid remembers the walls")
	_check(
		dm.is_wall(Vector3i(-1, 0, 0)) and not dm.is_wall(Vector3i(0, 0, 0)), "is_wall reads them"
	)

	dm.mark_hole(Vector3i(-1, 0, 0))
	_check(not dm.derive_wall_tiles().has(Vector3i(-1, 0, 0)), "a hole is never walled off")
	dm.mark_pit(Vector3i(2, 0, 0))
	_check(not dm.derive_wall_tiles().has(Vector3i(2, 0, 0)), "a pit is never walled off")
	dm.add_floor(Vector3i(0, -1, 2))
	_check(not dm.derive_wall_tiles().has(Vector3i(0, 0, 2)), "a lip with floor below stays open")
	var mech := Node.new()
	dm.register_mechanism(Vector3i(0, 0, -1), mech)
	_check(not dm.derive_wall_tiles().has(Vector3i(0, 0, -1)), "a mechanism's tile is not walled")
	dm.unregister_mechanism(Vector3i(0, 0, -1), mech)
	mech.free()
	_check(dm.derive_wall_tiles().has(Vector3i(0, 0, -1)), "...until the mechanism leaves")
	dm.queue_free()
	await get_tree().process_frame


func _check_entrance_and_exits() -> void:
	print("[entrance and exits]")
	var dm = _field(3, 3)
	_check(not dm.has_entrance() and not dm.has_exit(), "none declared at first")
	_check(dm.entrance_tile() == Vector3i.ZERO and dm.random_exit() == Vector3i.ZERO, "zero then")
	_check(dm.exit_tiles().is_empty(), "no exit tiles")
	dm.set_entrance(Vector3i(0, 0, 2))
	_check(
		dm.has_entrance() and dm.entrance_tile() == Vector3i(0, 0, 2), "the entrance is declared"
	)
	_check(dm.has_exit() and dm.exit_tiles() == [Vector3i(0, 0, 2)], "...and counts as an exit")
	dm.add_exit(Vector3i(0, 0, 2))
	_check(dm.exit_tiles().size() == 1, "an exit is never listed twice")
	dm.add_exit(Vector3i(2, 0, 0))
	_check(dm.exit_tiles().size() == 2, "a second exit is added")
	var seen := {}
	for i in 60:
		seen[dm.random_exit()] = true
	_check(
		seen.size() == 2 and seen.has(Vector3i(0, 0, 2)) and seen.has(Vector3i(2, 0, 0)),
		"random_exit draws among them"
	)
	var copy: Array = dm.exit_tiles()
	copy.clear()
	_check(dm.exit_tiles().size() == 2, "exit_tiles hands out a copy")
	dm.queue_free()


func _check_free_tiles() -> void:
	print("[free tiles]")
	var dm = _field(3, 3)
	var mid := Vector3i(1, 0, 1)
	_check(dm.tile_search.free_tile_near(mid) == mid, "a free tile is its own answer")
	var sitter := Fixture.actor(self, mid)
	dm.reserve(mid, sitter)
	var near: Vector3i = dm.tile_search.free_tile_near(mid)
	_check(
		near != mid and absi(near.x - 1) + absi(near.z - 1) == 1,
		"an occupied one gives a neighbour"
	)
	_check(
		dm.tile_search.free_tile_near(Vector3i(9, 0, 9)) == Vector3i(9, 0, 9),
		"off the floor: unchanged"
	)
	var around: Array = dm.tile_search.free_tiles_near(mid, 1)
	_check(around.size() == 4 and not around.has(mid), "radius 1 around the middle: four tiles")
	_check(
		dm.tile_search.free_tiles_near(Vector3i(0, 0, 0), 2).size() == 4,
		"radius 2 in a corner: four free"
	)
	dm.reserve(Vector3i(1, 0, 0), Fixture.actor(self, Vector3i(1, 0, 0)))
	_check(
		not dm.tile_search.free_tiles_near(mid, 1).has(Vector3i(1, 0, 0)),
		"an occupied tile is not free"
	)
	_check(dm.tile_search.free_tiles_near(mid, 0).is_empty(), "radius 0 leaves nothing")
	dm.queue_free()


func _check_walking_distances() -> void:
	print("[walking distances]")
	var dm = _field(4, 1)
	var steps: Dictionary = dm.tile_search.walking_distances(Vector3i(0, 0, 0), 2)
	_check(steps.get(Vector3i(0, 0, 0)) == 0, "the origin is at zero")
	_check(steps.get(Vector3i(2, 0, 0)) == 2, "two steps along")
	_check(not steps.has(Vector3i(3, 0, 0)), "past the budget is out of reach")
	dm.reserve(Vector3i(1, 0, 0), Fixture.actor(self, Vector3i(1, 0, 0)))
	_check(
		dm.tile_search.walking_distances(Vector3i(0, 0, 0), 3).size() == 1,
		"an occupied tile bars the way"
	)
	dm.queue_free()


func _check_random_floor_tile() -> void:
	print("[random floor tile]")
	var dm = _field(2, 1)
	var a := Vector3i(0, 0, 0)
	var b := Vector3i(1, 0, 0)
	_check(dm.tile_search.random_floor_tile(a) == b, "never the excluded tile")
	dm.safe_areas.mark([b])
	_check(dm.tile_search.random_floor_tile(a) == b, "a safe area is fair game by default")
	_check(
		dm.tile_search.random_floor_tile(a, true) == a,
		"...but avoided on request, falling back to `exclude`"
	)
	dm.reserve(b, Fixture.actor(self, b))
	_check(dm.tile_search.random_floor_tile(a) == a, "an occupied tile is not a candidate")
	dm.queue_free()


func _check_teleporting() -> void:
	print("[teleporting]")
	var dm = _field(3, 1)
	var who := Fixture.actor(self, Vector3i(0, 0, 0))
	dm.reserve(who.tile, who)
	_check(
		dm.teleport_actor_to(who, Vector3i(7, 0, 0)) == Vector3i(0, 0, 0), "off the floor: stays"
	)
	var landed: Vector3i = dm.teleport_actor_to(who, Vector3i(2, 0, 0))
	_check(landed == Vector3i(2, 0, 0) and who.tile == landed, "moves to a free tile")
	_check(
		dm.occupant_at(Vector3i(2, 0, 0)) == who and dm.occupant_at(Vector3i(0, 0, 0)) == null,
		"occupancy follows"
	)
	var other := Fixture.actor(self, Vector3i(0, 0, 0))
	dm.reserve(other.tile, other)
	landed = dm.teleport_actor_to(other, Vector3i(2, 0, 0))
	_check(landed == Vector3i(1, 0, 0), "an occupied destination falls back to a neighbour")
	var back: Vector3i = dm.teleport_actor(other)
	_check(back != Vector3i(1, 0, 0) and dm.is_floor(back), "a random teleport lands elsewhere")
	dm.queue_free()
