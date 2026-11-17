## Headless check of the dungeon loader: small plans built into a bare [DungeonManager], then the
## real frozen lake through the exploration scene, as the Dungeons tab starts it.
##
## Run with: Godot --headless --path . res://scenes/dev/dungeon_loader_check.tscn
## As a start scene rather than --script; see geometry_check.gd.
extends Node

const Parser := preload("res://scripts/dungeon/dungeon_map_parser.gd")
const Loader := preload("res://scripts/dungeon/dungeon_loader.gd")
const Plan := preload("res://scripts/dungeon/dungeon_plan.gd")
const ScenarioCatalog := preload("res://scripts/dev/scenario_catalog.gd")
const Trap := preload("res://scripts/exploration/mechanisms/trap.gd")
const Chest := preload("res://scripts/exploration/mechanisms/chest.gd")
const Gateway := preload("res://scripts/exploration/mechanisms/gateway.gd")
const Stairs := preload("res://scripts/exploration/mechanisms/stairs.gd")
const Elevator := preload("res://scripts/exploration/mechanisms/elevator.gd")
const ExaminableDecor := preload("res://scripts/exploration/mechanisms/examinable_decor.gd")
const EXPLORATION := preload("res://scenes/exploration/exploration.tscn")

var _fails: Array[String] = []


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  OK   %s" % label)
	else:
		print("  FAIL %s" % label)
		_fails.append(label)


func _ready() -> void:
	await get_tree().process_frame
	_check_layout_and_mechanisms()
	_check_walls_and_teleports()
	_check_water()
	await _check_the_frozen_lake()
	if _fails.is_empty():
		print("All checks pass.")
		get_tree().quit(0)
	else:
		print("%d check(s) failed." % _fails.size())
		get_tree().quit(1)


func _plan_of(text: String) -> Plan:
	var plan := Plan.new()
	plan.slug = &"fixture"
	Parser.new().read_floor(plan, text, "fixture.map")
	return plan


func _build(text: String) -> Dictionary:
	var dm := DungeonManager.new()
	add_child(dm)
	var built := Loader.build_plan(_plan_of(text), dm)
	built["dm"] = dm
	return built


func _mechanisms(dm: DungeonManager, script) -> Array:
	var out: Array = []
	for child in dm.get_children():
		if child.get_script() == script:
			out.append(child)
	return out


func _check_layout_and_mechanisms() -> void:
	var text := (
		"[floor]\ny = 0\n[grid]\n"
		+ "#########\n#E.T.cg.X#\n#.......=#\n#########\n"
		+ "[legend]\nT = trap type=teleport reactivates=true\nc = chest trapped=true loot=spade,rune_stone\n"
		+ "g = gate type=locked edge=E currency=spade tier=late\n= = bridge over=void\n"
		+ "[tiles]\nB2 facing=E exit_edge=W\nD3 decor type=posters\nF3 trap type=poison poison_turns=7\n"
	)
	var built := _build(text)
	var dm: DungeonManager = built["dm"]
	var plan: Plan = built["plan"]
	_check(dm.layout.floor_tiles().size() == plan.floor_tiles.size(), "every floor tile is laid")
	_check(built["start"] == Vector3i(1, 0, 1), "the player starts on the entrance")
	_check(is_equal_approx(built["yaw"], -PI / 2.0), "...facing east, as the entrance says")
	_check(dm.layout.exit_tiles().has(Vector3i(8, 0, 1)), "an exit is declared")
	_check(dm.layout.has_entrance(), "so is the entrance")
	var traps := _mechanisms(dm, Trap)
	_check(traps.size() == 2, "both traps are placed")
	var tele: Trap = null
	var poison: Trap = null
	for t in traps:
		if t.kind == Trap.Kind.TELEPORT:
			tele = t
		else:
			poison = t
	_check(tele != null and tele.reactivates, "a teleport trap that rearms")
	_check(poison != null and poison.poison_turns == 7, "a poison trap with its own duration")
	var chests := _mechanisms(dm, Chest)
	_check(chests.size() == 1 and chests[0].is_trap, "a trapped chest")
	_check(chests[0].fixed_loot == [&"spade", &"rune_stone"], "...with its loot, as names")
	var gates := _mechanisms(dm, Gateway)
	_check(gates.size() == 1 and gates[0].kind == Gateway.Kind.LOCKED, "a locked gate")
	_check(gates[0].edge_dir == Vector3i(1, 0, 0), "...on its east edge")
	_check(gates[0].cost_currency == &"spade" and gates[0].cost_tier == Gateway.CostTier.LATE, "...with its price")
	_check(_mechanisms(dm, ExaminableDecor)[0].decor_type == ExaminableDecor.DecorType.POSTERS, "decor type")
	_check(dm.layout.pit_tiles().has(Vector3i(8, 0, 2)), "a bridge tile is a pit")
	_check(dm.layout.is_floor(Vector3i(8, 0, 2)), "...and walkable")
	# Stairs and lifts
	var two := (
		"[floor]\ny = 0\n[grid]\n#####\n#E^##\n#####\n[legend]\n^ = stairs dir=up face=E\n"
		+ "[tiles]\nB2 facing=E exit_edge=W\n"
	)
	var up := _build(two)
	var stairs := _mechanisms(up["dm"], Stairs)
	_check(stairs.size() == 1 and stairs[0].level_delta == 1, "stairs climb")
	_check(stairs[0].face_dir == Vector3i(1, 0, 0), "...towards their face")
	_check(not up["dm"].layout.is_floor(Vector3i(2, 0, 1)), "the stairs' own tile is not floor")
	var lifts := _build(
		(
			"[floor]\ny = 0\n[grid]\n#####\n#E.L#\n#####\n[legend]\nL = lift path=D2@1 linked=B2\n"
			+ "[tiles]\nB2 lift path=D2@1\n"
		)
	)
	var elevators := _mechanisms(lifts["dm"], Elevator)
	_check(elevators.size() == 2, "two lifts")
	var linked := 0
	for e in elevators:
		linked += e.linked.size()
	_check(linked == 1, "one is linked to the other")
	_check(elevators[0].path == [Vector3i(3, 1, 1)] or elevators[1].path == [Vector3i(3, 1, 1)], "a lift's path is in tiles")


func _check_walls_and_teleports() -> void:
	# A wall on the upper storey over ground is a wall, not a drop.
	var text_ground := "[floor]\ny = 0\n[grid]\n#####\n#...#\n#####\n"
	var text_up := "[floor]\ny = 1\n[grid]\n#####\n#E.##\n#####\n"
	var plan := Plan.new()
	Parser.new().read_floor(plan, text_ground, "g.map")
	Parser.new().read_floor(plan, text_up, "u.map")
	var dm2 := DungeonManager.new()
	add_child(dm2)
	Loader.build_plan(plan, dm2)
	var wall := Vector3i(3, 1, 1)
	_check(dm2.layout.is_declared_wall(wall), "a # is a declared wall")
	_check(dm2.layout.fall_landing(wall) == wall, "...nobody falls into it, with ground below")
	_check(dm2.layout.remember_walls().has(wall), "...and it is drawn, floor touching it")
	_check(dm2.layout.fall_landing(Vector3i(4, 1, 1)) == Vector3i(4, 1, 1), "(nothing below the far wall)")
	# No teleport
	var zone := (
		"[floor]\ny = 0\n[grid]\n###############\n#E............#\n###############\n"
		+ "[zones]\npocket tags=no_teleport rect=D2:N2\n"
	)
	var built := _build(zone)
	var tiles: Dictionary = built["plan"].tiles_with_tag("no_teleport")
	_check(tiles.size() == 11, "the zone has its tiles")
	var landed_inside := 0
	for i in 400:
		if tiles.has(built["dm"].tile_search.random_floor_tile(Vector3i(1, 0, 1))):
			landed_inside += 1
	_check(landed_inside == 0, "a random teleport never lands in a no_teleport zone")


## Water and the `[water] emerge` rule, in a small plan: a pond tile, a plank over water, and the
## emerge tile, all of them reaching the layout.
func _check_water() -> void:
	var plan := _plan_of(
		"[floor]\ny = 0\n[grid]\n#####\n#E=.#\n#.~.#\n#####\n[legend]\n= = bridge over=water\n"
	)
	plan.rules = {"water": {"emerge": "B2"}}
	var dm := DungeonManager.new()
	add_child(dm)
	Loader.build_plan(plan, dm)
	var pond := Vector3i(2, 0, 2)
	_check(dm.layout.is_water(pond) and not dm.layout.is_floor(pond), "a ~ is water, not floor")
	_check(dm.layout.plank_over_water(Vector3i(2, 0, 1)), "a bridge over=water is a plank over water")
	_check(dm.layout.water_tiles().size() == plan.water_tiles.size(), "every water tile is laid")
	_check(
		dm.layout.has_emerge_tile() and dm.layout.emerge_tile() == Vector3i(1, 0, 1),
		"[water] emerge is the layout's emerge tile"
	)
	_check(not dm.layout.derive_wall_tiles().has(pond), "...and the water is not walled off")
	var bare := DungeonManager.new()
	add_child(bare)
	Loader.build_plan(_plan_of("[floor]\ny = 0\n[grid]\n###\n#E#\n###\n"), bare)
	_check(not bare.layout.has_emerge_tile(), "a dungeon with no [water] rule has no emerge tile")


func _check_the_frozen_lake() -> void:
	# The fixtures above are dungeons too, in the "dungeon" group, and the player would find the
	# first of them rather than the lake's own.
	for child in get_children():
		if child is DungeonManager:
			child.free()
	ScenarioCatalog.selected_dungeon = &"norgzevod_frozen_lake"
	var scene := EXPLORATION.instantiate()
	add_child(scene)
	await get_tree().process_frame
	var dm: DungeonManager = scene.get_node("DungeonManager")
	var player = scene.get_node("Player")
	var plan = Parser.load_slug(&"norgzevod_frozen_lake")
	_check(player.tile == plan.entrance, "the lake: the player stands on the entrance, J29 on floor -1")
	_check(is_equal_approx(wrapf(player.rotation.y, -PI, PI), 0.0), "...facing north")
	_check(dm.layout.floor_tiles().size() == plan.floor_tiles.size(), "the lake: every floor tile is laid")
	for kind in [&"chest", &"gate", &"stairs", &"bridge", &"trap", &"cracked_wall", &"crystal", &"litter", &"crumbly"]:
		var wanted := 0
		for p in plan.placements:
			if p["kind"] == kind:
				wanted += 1
		var scripts := {
			&"chest": Chest, &"gate": Gateway, &"stairs": Stairs, &"trap": Trap,
		}
		if scripts.has(kind):
			_check(_mechanisms(dm, scripts[kind]).size() == wanted, "the lake: %d %s placed" % [wanted, kind])
	# Every flight lands on floor.
	var stranded := 0
	for st in _mechanisms(dm, Stairs):
		var from: Vector3i = st.tile - st.face_dir
		if not dm.is_floor(from) or not dm.is_floor(st.stairs_destination(from, st.face_dir)):
			stranded += 1
	_check(stranded == 0, "the lake: no staircase is stranded")
	# The east pocket takes no random teleport.
	var pocket: Dictionary = plan.tiles_with_tag("no_teleport")
	_check(pocket.size() == 6, "the lake: the pocket is 6 tiles")
	var hits := 0
	for i in 1500:
		if pocket.has(dm.tile_search.random_floor_tile(Vector3i(0, 0, 0))):
			hits += 1
	_check(hits == 0, "the lake: nothing teleports into the pocket")
	_check(dm.config == null, "the lake: no config yet, so no group appears")
	# Water: laid, never walled off, and the emerge tile is F25 of floor 0.
	_check(not plan.water_tiles.is_empty(), "the lake has water")
	_check(
		dm.layout.water_tiles().size() == plan.water_tiles.size(),
		"the lake: every water tile is laid"
	)
	_check(
		dm.layout.has_emerge_tile() and dm.layout.emerge_tile() == Vector3i(5, 0, 24),
		"the lake: the emerge tile is F25 on floor 0"
	)
	_check(dm.is_floor(dm.layout.emerge_tile()), "...and it is floor")
	var walled_water := 0
	for w in dm.layout.derive_wall_tiles():
		if dm.layout.is_water(w):
			walled_water += 1
	_check(walled_water == 0, "the lake: no water tile is walled off")
	# A step into the lake from its shore is blocked like a wall — and, when some storey lies
	# beneath the water, not a fall onto it. Such a shore is preferred.
	var shore := Vector3i.ZERO
	var pond := Vector3i.ZERO
	var over_floor := false
	for w in plan.water_tiles:
		if not dm.layout.is_open_water(w):
			continue
		var below: bool = dm.layout.fall_landing(w) != w
		for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			if dm.is_walkable(w + d) and (shore == Vector3i.ZERO or (below and not over_floor)):
				shore = w + d
				pond = w
				over_floor = below
	_check(shore != Vector3i.ZERO, "the lake has a shore to stand on")
	_check(over_floor, "...with floor beneath the water, which a step must not fall to")
	player.teleport_to(shore)
	player.face_tile(pond)
	await player.try_move(Vector3.FORWARD)
	_check(player.tile == shore, "the lake: a step into the water is blocked")
	scene.queue_free()
	ScenarioCatalog.selected_dungeon = &""
