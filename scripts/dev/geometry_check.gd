## Headless check of the dungeon's geometry: scale (a cell is 1 m, eyes at 0.6 m), thin slabs
## (you can walk under a storey), gateways sitting on edges. Walks every test scenario and exits
## 1 if any of them regresses.
##
## Run with: Godot --headless --path . res://scenes/dev/geometry_check.tscn
## As a start scene rather than --script: under --script the autoloads do not exist yet, and the
## exploration scripts that reference them fail to compile.
extends Node

const ScenarioCatalog := preload("res://scripts/dev/scenario_catalog.gd")
const EXPLORATION := preload("res://scenes/exploration/exploration.tscn")
const RIVAL_SCENE := preload("res://scenes/exploration/rival/rival.tscn")

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
	await get_tree().process_frame  # let the autoloads and the root settle
	# Walk the CATALOGUE rather than a frozen list: a scenario added to `data/scenarios/` is
	# checked automatically, and if it has no builder, ScenarioCatalog.build() says so instead of
	# silently falling back to another one.
	for scenario in ScenarioCatalog.list():
		await _run_scenario(scenario.id)
	print("")
	if _fails.is_empty():
		print("ALL OK")
	else:
		print("FAILURES: %s" % [_fails])
	get_tree().quit(0 if _fails.is_empty() else 1)


func _run_scenario(id: StringName) -> void:
	print("[%s]" % id)
	ScenarioCatalog.selected_id = id
	var scene = EXPLORATION.instantiate()
	get_tree().root.add_child(scene)
	await get_tree().process_frame  # the scene's _ready: grid built, mechanisms registered
	var dm = scene.get_node("DungeonManager")
	var player = scene.get_node("Player")

	# Scale: a wall block is 1 m³, and eyes sit below the top of the wall.
	_check(dm.CELL_SIZE == 1.0, "cell is 1 m")
	var cam_rig = player.get_node("CameraRig")
	var eye_y: float = player.global_position.y + cam_rig.position.y
	var floor_y: float = dm.cell_to_world(player.cell).y
	_check(
		is_equal_approx(eye_y - floor_y, dm.EYE_HEIGHT),
		"eyes %.2f m above the floor" % (eye_y - floor_y)
	)
	_check(eye_y - floor_y < dm.CELL_SIZE, "eyes below the top of the walls")

	# Generated geometry: thin slabs (ceilings you can walk under) and solid wall blocks.
	var slabs := 0
	var walls := 0
	var misplaced := 0
	var too_thick := 0
	for child in dm.get_children():
		var mi := child as MeshInstance3D
		if mi == null or not (mi.mesh is BoxMesh):
			continue
		var s: Vector3 = mi.mesh.size
		if not is_equal_approx(s.x, dm.CELL_SIZE):
			continue  # a mechanism's visual, not part of the grid
		var top: float = mi.position.y + s.y * 0.5
		if is_equal_approx(s.y, dm.FLOOR_THICKNESS):
			slabs += 1
			# Top face level with a storey's floor, or a pit's, offset by PIT_DEPTH.
			if not (_on_level(top, dm.CELL_SIZE) or _on_level(top + dm.PIT_DEPTH, dm.CELL_SIZE)):
				misplaced += 1
		elif is_equal_approx(s.y, dm.CELL_SIZE):
			walls += 1
			# The block fills ITS OWN cell's volume, without biting into the storey above.
			if not _on_level(top, dm.CELL_SIZE):
				misplaced += 1
		else:
			too_thick += 1
	_check(
		slabs > 0,
		(
			"%d thin slabs (floor doubling as a walk-under ceiling) + %d 1 m³ wall blocks"
			% [slabs, walls]
		)
	)
	_check(misplaced == 0, "every slab and wall aligned on its storey")
	_check(too_thick == 0, "no floor rendered as a solid block")
	_check_no_double_ground(dm, slabs)

	if id == &"movement":
		await _check_bottomless(dm, player)
		_check_rival_sprite_box(dm)
	if id == &"traps":
		_check_traps_hidden_on_map(dm)
		_check_disarray_mouse(player)
	if id == &"gates":
		await _check_gates(dm, player)
	if id == &"stairs":
		await _check_stairs(dm, player)
	if id == &"bridge":
		_check_bridge(dm)
		_check_bridge_disarray(scene, dm, player)
	if id == &"bridge_rival":
		_check_bridge(dm)
		await _check_rival_on_bridge(dm)

	scene.queue_free()
	# Purge: the next scenario has to start from an empty dungeon.
	get_tree().root.remove_child(scene)
	scene.free()


## Guardrails ("Walls + Decors / Guardrails"): laid on the edge like a gateway that never opens,
## they stop a storey's edge being crossed WITHOUT filling in the drop behind it and without
## costing a cell. The same edge, two cells further, stays open — and drops you.
func _check_guardrails(dm) -> void:
	var edge := Vector3i(1, 0, 0)
	var railed := Vector3i(6, 4, 4)  # the protected east edge
	var open_edge := Vector3i(6, 4, 6)  # same edge, two steps further: nothing
	var rails: Array = dm.edge_mechanisms_between(railed, railed + edge)
	_check(rails.size() == 1, "guardrail sitting on the east edge")
	_check(
		dm.mechanisms_at(railed).is_empty() and dm.mechanisms_at(railed + edge).is_empty(),
		"a guardrail occupies no cell"
	)
	_check(
		dm.is_floor(railed) and dm.is_walkable(railed),
		"the cell behind the guardrail stays walkable"
	)
	_check(
		dm.is_edge_blocked(railed, railed + edge) and dm.is_edge_blocked(railed + edge, railed),
		"protected edge: crossing refused in both directions"
	)
	_check(
		dm.fall_landing(railed + edge) != railed + edge,
		"the drop is still there behind the guardrail (it fills nothing in)"
	)
	_check(
		not dm.is_edge_blocked(open_edge, open_edge + edge),
		"two cells further, the same edge is open"
	)
	_check(
		dm.fall_landing(open_edge + edge) == Vector3i(7, 0, 6),
		"and it drops you all the way down (4 units)"
	)
	_check_rival_stopped_by_rail(dm)
	if rails.size() == 1:
		_check(
			rails[0].HEIGHT < dm.EYE_HEIGHT,
			(
				"guardrail below eye height (%.2f m < %.2f m): does not cut the view"
				% [rails[0].HEIGHT, dm.EYE_HEIGHT]
			)
		)


## A guardrail holds RIVALS back too: one that would jump to give chase cannot step over the
## protected edge — it needs an open one.
func _check_rival_stopped_by_rail(dm) -> void:
	var post := Vector3i(6, 4, 4)  # behind the east edge's guardrail
	var below := Vector3i(7, 0, 4)  # what it would aim for jumping over
	var rival = RIVAL_SCENE.instantiate()
	rival.position = dm.cell_to_world(post)
	dm.add_child(rival)
	var brink: Vector3i = rival._open_drop_edge(below)
	_check(
		brink != post + Vector3i(1, 0, 0),
		"the rival does not jump over the guardrail (edge chosen: %s)" % brink
	)
	rival.queue_free()


## Per the design doc's "Walls + Decors", a wall block can serve as the floor of the storey
## above. A floor cell resting on a wall must therefore NOT get an extra slab — that would put
## two top faces exactly coplanar, doubling the geometry and z-fighting. The exact expected slab
## count is checked: non-pit floors with no wall below, plus the bottom of the pits that overhang
## nothing.
func _check_no_double_ground(dm, slabs: int) -> void:
	var walls: Dictionary = dm.derive_wall_cells()
	var expected := 0
	var on_walls := 0
	for c in dm._floor:
		if dm._pit.has(c):
			continue
		if walls.has(c + Vector3i.DOWN):
			on_walls += 1
		else:
			expected += 1
	for c in dm._pit:
		if dm.fall_landing(c) == c:
			expected += 1
	_check(
		slabs == expected,
		(
			"%d slab(s) expected, %d rendered — %d floor(s) carried by a wall, with no slab"
			% [expected, slabs, on_walls]
		)
	)


## Whether `v` lands on a multiple of `step`, within floating-point error — including just
## below it, where fposmod returns nearly `step` rather than nearly 0.
func _on_level(v: float, step: float) -> bool:
	var r := fposmod(v, step)
	return minf(r, step - r) < 0.001


## Disarray and free look. The design doc no longer makes an exception for the free camera: a
## mouse gesture is deflected a quarter turn at unchanged MAGNITUDE, so as not to commit a turn
## the player never asked for. But it only COUNTS the trap down if it actually commits a turn —
## otherwise disarray could be drained by waggling the cursor, without spending a single turn.
func _check_disarray_mouse(player) -> void:
	var handler = player.get_node("PlayerInputHandler")
	var aff = player.affliction
	while aff.has_disarray():
		aff.consume_move()
	aff.add_disarray(30)
	# None of these gestures consumes anything: they all peek at the SAME head entry. Bring it
	# onto a deflected one, or the test would depend on how the queue was shuffled.
	while aff.has_disarray() and not aff.peek_move():
		aff.consume_move()
	_check(aff.peek_move(), "queue brought onto a deflected move")

	# --- Gestures that commit NO turn: deflected, but free ---
	var gesture := Vector2(12.0, -5.0)  # too short to cross commit_angle
	var before: int = aff.remaining_disarray()
	var deviated := 0
	var bad_length := 0
	var bad_angle := 0
	var unstable := 0
	for i in range(24):
		var first: Vector2 = handler._disarrayed_mouse(gesture)
		# A second event in the SAME gesture: the cursor turns, the offset does not.
		var second: Vector2 = handler._disarrayed_mouse(gesture)
		if not first.is_equal_approx(second):
			unstable += 1
		if not is_equal_approx(first.length(), gesture.length()):
			bad_length += 1
		if not first.is_equal_approx(gesture):
			deviated += 1
			if int(roundf(rad_to_deg(gesture.angle_to(first)))) % 90 != 0:
				bad_angle += 1
		handler._process(handler.MOUSE_BURST_IDLE + 0.01)  # the cursor stops: gesture closed
	_check(unstable == 0, "the offset holds for the whole gesture, cursor turned mid-way")
	_check(bad_length == 0, "gesture magnitude unchanged (no unintended turn)")
	_check(
		deviated == 24, "all 24 gestures deflected (%d) — the head entry does not move" % deviated
	)
	_check(bad_angle == 0, "every deflection is a quarter turn (90 / 180 / 270 degrees)")
	_check(
		aff.remaining_disarray() == before,
		"24 gestures committing no turn: nothing counted down (%d)" % aff.remaining_disarray()
	)

	# --- A gesture that DOES commit a turn: that one counts as a move ---
	# A diagonal wide enough to cross commit_angle on the yaw axis whichever quarter turn is
	# rolled — a deflection must not hand out a free turn.
	var sweep := Vector2(400.0, 400.0)
	var turns := 0
	var spent_wrong := 0
	for i in range(8):
		handler._yaw_offset = 0.0  # each sweep starts from neutral, or the leftover decides
		var turn_before: int = _dungeon_turn(player)
		var left: int = aff.remaining_disarray()
		handler._apply_mouse_look(sweep)
		handler._process(0.016)  # _fold_offset commits the turn
		var committed: int = _dungeon_turn(player) - turn_before
		turns += committed
		if aff.remaining_disarray() != left - committed:
			spent_wrong += 1
		handler._process(handler.MOUSE_BURST_IDLE + 0.01)  # next gesture
	_check(turns == 8, "every wide sweep commits a turn (%d/8)" % turns)
	_check(spent_wrong == 0, "a committed turn takes exactly one disarray move")

	# --- Disarray spent: free look goes straight again ---
	while aff.has_disarray():
		aff.consume_move()
	handler._process(handler.MOUSE_BURST_IDLE + 0.01)
	_check(
		handler._disarrayed_mouse(gesture).is_equal_approx(gesture),
		"disarray spent: the gesture is no longer deflected"
	)


## The current turn number, read from the dungeon the player belongs to.
func _dungeon_turn(player) -> int:
	return player.get_parent().get_node("DungeonManager").turn_count


func _check_traps_hidden_on_map(dm) -> void:
	var shown := 0
	var traps := 0
	for m in dm.get_children():
		if not (m is Node) or not m.has_method("shows_on_map") or m.get("kind") == null:
			continue
		if not "revealed" in m:
			continue
		traps += 1
		if m.shows_on_map():
			shown += 1
		m.revealed = false
		_check(not m.shows_on_map(), "hidden trap: absent from the map")
		m.revealed = true
		_check(m.shows_on_map(), "known trap: present on the map")
	_check(traps > 0 and shown == traps, "%d trap(s) in the test scenario, all revealed" % traps)


## The design doc's "Visuals + Sounds": a rival sprite fits in 90 cm x 90 cm. Tried on a species
## WIDER THAN IT IS TALL (jézal, 2000 x 1898), where fitting on height alone would spill into the
## neighbouring cells.
func _check_rival_sprite_box(dm) -> void:
	for species in [&"jezal", &"jezal", &"fliritus", &"ravbak"]:
		var rival = RIVAL_SCENE.instantiate()
		rival.species_id = species
		rival.position = dm.cell_to_world(Vector3i(0, 0, 0))
		dm.add_child(rival)
		var sprite := rival.get_node_or_null("Sprite3D") as Sprite3D
		if sprite != null and sprite.texture != null:
			var w: float = sprite.texture.get_width() * sprite.pixel_size
			var h: float = sprite.texture.get_height() * sprite.pixel_size
			_check(
				w <= rival.world_height + 0.001 and h <= rival.world_height + 0.001,
				"sprite %s: %.2f x %.2f m, fits in %.2f m" % [species, w, h, rival.world_height]
			)
			_check(
				is_equal_approx(sprite.position.y, h * 0.5),
				"sprite %s rests on the floor" % species
			)
		rival.queue_free()


## A BOTTOMLESS fall should not exist: a cell with nothing below it is rendered as a wall. But if
## level design marks an outright hole, entering it devitalises the duo — a floor you never reach
## is a floor too far down to survive — instead of blocking silently.
func _check_bottomless(dm, player) -> void:
	var hole := Vector3i(3, 0, -1)  # in front of the start: normally a perimeter wall
	var plain := Vector3i(2, 0, -1)  # same row, left as it is
	_check(not dm.is_bottomless(plain), "a merely absent cell is a wall, and no fall")
	dm.mark_hole(hole)
	_check(dm.is_bottomless(hole), "an outright hole is a bottomless fall")
	_check(not dm.derive_wall_cells().has(hole), "an outright hole is not plugged by a wall")
	var wiped := [false]
	GameSession.party_wiped.connect(func() -> void: wiped[0] = true, CONNECT_ONE_SHOT)
	await player.fall_forever(hole)
	_check(wiped[0], "bottomless fall: duo devitalised, and so out of the dungeon")


## Gateways: on the edge, both cells stay walkable, the passage is barred while the gateway is
## closed, and the action is offered from either side.
func _check_gates(dm, player) -> void:
	var a := Vector3i(1, 0, 3)
	var b := Vector3i(1, 0, 4)
	_check(dm.is_floor(a) and dm.is_floor(b), "both cells around a gateway are floor")
	_check(
		dm.mechanisms_at(a).is_empty() and dm.mechanisms_at(b).is_empty(),
		"a gateway occupies no cell"
	)
	var gate = dm.edge_mechanisms_between(a, b)[0]
	_check(gate != null, "gateway found on the edge")
	_check(dm.edge_mechanisms_between(b, a).size() == 1, "symmetric edge, same from both sides")
	# A locked, closed gateway bars the passage both ways and leaves the cells free.
	var la := Vector3i(1, 0, 6)
	var lb := Vector3i(1, 0, 7)
	_check(
		dm.is_edge_blocked(la, lb) and dm.is_edge_blocked(lb, la), "closed gateway: passage barred"
	)
	_check(dm.is_walkable(la) and dm.is_walkable(lb), "closed gateway: cells still walkable")
	_check(not dm.can_step(la, lb), "can_step refuses to cross a closed gateway")
	# Actions reachable from both sides: open, meditate.
	var from_south: Array = dm.actions_for(la, Vector3i(0, 0, 1), player)
	var from_north: Array = dm.actions_for(lb, Vector3i(0, 0, -1), player)
	_check(
		from_south.size() == 1 and from_south[0].id == &"open_gate", "open action from the south"
	)
	_check(
		from_north.size() == 1 and from_north[0].id == &"open_gate", "open action from the north"
	)
	# Opening it clears the passage.
	var locked = dm.edge_mechanisms_between(la, lb)[0]
	# The price is ANNOUNCED by the gateway, on both faces — the design doc wants it "shown on the
	# gate itself", "on both sides, at eye level" — otherwise the player would pay to find out.
	_check_locked_gate_price(locked)
	_check(locked.try_open_locked(), "paying for the locked gateway")
	_check(dm.can_step(la, lb) and dm.can_step(lb, la), "open gateway: passage clear both ways")
	var cleared := true
	for child in locked.get_children():
		if child is Label3D and child.text != "":
			cleared = false
	_check(cleared, "open gateway: the price is no longer shown")
	# What blocks sight blocks interaction: the heap BEHIND the closed meditation gateway is not
	# actionable, while the gateway itself still offers "meditate".
	var mz := Vector3i(1, 0, 9)
	var toward := Vector3i(0, 0, 1)
	_check(dm.is_edge_opaque(mz, mz + toward), "closed gateway: opaque edge")
	var ids := _action_ids(dm.actions_for(mz, toward, player))
	_check(ids == [&"meditate"], "behind a closed gateway: no decor action (%s)" % [ids])
	_check_meditation_streak(dm, player)
	# Open gateway: the heap is visible again, and so actionable.
	_check(not dm.is_edge_opaque(mz, mz + toward), "open gateway: transparent edge")
	var after := _action_ids(dm.actions_for(mz, toward, player))
	_check(
		&"examine" in after or &"recycle" in after,
		"open gateway: the decor actions behind it come back (%s)" % [after]
	)


## A locked gateway shows its price on EACH face, at eye height, while it is closed — and has
## nothing left to say once open.
func _check_locked_gate_price(locked) -> void:
	var labels := []
	for child in locked.get_children():
		if child is Label3D:
			labels.append(child)
	_check(labels.size() == 2, "price written on both faces of the gateway (%d)" % labels.size())
	var expected := (
		"%d × %s" % [locked.locked_cost(), tr(GameData.object(locked.cost_currency).name_key())]
	)
	var shown := true
	for label in labels:
		if label.text != expected:
			shown = false
		_check(
			absf(label.position.y - DungeonManager.EYE_HEIGHT) < 0.01,
			"price at eye height (y = %.2f m)" % label.position.y
		)
	_check(shown, 'price legible on both faces ("%s")' % expected)


func _action_ids(actions: Array) -> Array:
	var ids := []
	for a in actions:
		ids.append(a.id)
	return ids


## Meditation gateway. The design doc: "3 CONSECUTIVE times in front of them" — the streak only
## counts while the player holds their spot; moving or turning away resets it.
func _check_meditation_streak(dm, _player) -> void:
	var ma := Vector3i(1, 0, 9)
	var toward := Vector3i(0, 0, 1)
	var gate = dm.edge_mechanisms_between(ma, ma + toward)[0]
	# The player is elsewhere during this test, which is precisely what should break the streak.
	_check(not gate.meditate(ma, toward), "1st meditation: gateway still closed")
	_check(not gate.meditate(ma, toward), "2nd meditation: gateway still closed")
	gate.on_turn(1)  # a turn elapses with the player off their spot, breaking the streak
	_check(not gate.is_open(), "streak broken: the gateway does not open")
	_check(not gate.meditate(ma, toward), "after the break, back to 1/3")
	_check(not gate.meditate(ma, toward), "2/3")
	_check(gate.meditate(ma, toward), "3 consecutive meditations: gateway open")
	# The edge is clear. The cell beyond carries a heap, an obstacle, so THAT is what blocks now,
	# not the gateway.
	_check(not dm.is_edge_blocked(ma, ma + toward), "meditation gateway open: edge cleared")


## Narrow bridge: every plank overhangs real floor, so a fall lands somewhere and takes the normal
## damage for its depth, and the climb back from the bottom does end on floor.
func _check_bridge(dm) -> void:
	var planks := []
	for child in dm.get_children():
		if child.has_method("engage") and child.has_method("direction"):
			planks.append(child.cell)
	_check(planks.size() > 0, "%d bridge cells" % planks.size())
	var landed := 0
	var depth := 0
	for c in planks:
		var landing: Vector3i = dm.fall_landing(c)
		if landing != c and landing.y < c.y:
			landed += 1
			depth = maxi(depth, c.y - landing.y)
	_check(
		landed == planks.size(),
		(
			"every plank overhangs floor (%d/%d, a ravine %d storeys deep)"
			% [landed, planks.size(), depth]
		)
	)
	_check(depth >= 2, "ravine more than one storey deep, so fall damage scales with depth")
	# The climb back: each upward flight starts from a walkable cell and arrives on floor.
	var flights := 0
	for child in dm.get_children():
		if not child.has_method("stairs_destination") or child.level_delta <= 0:
			continue
		flights += 1
		var from: Vector3i = child.cell - child.face_dir  # the cell the flight is approached from
		var dest: Vector3i = child.stairs_destination(from, child.face_dir)
		_check(
			dm.is_walkable(from) and dm.is_floor(dest),
			"flight %s: %s -> %s walkable" % [child.cell, from, dest]
		)
	_check(flights >= 2, "%d flights to climb from the bottom back to the start" % flights)


## The bridge counts disarray down cell by cell, because a cell crossed IS a move, and the arrival
## cell has no way out but the bridge — otherwise the disarray would be wasted wandering a
## platform instead of testing the bridge under it.
func _check_bridge_disarray(scene, dm, player) -> void:
	var arrival := Vector3i(1, 2, 7)
	_check(dm.is_floor(arrival), "arrival cell %s" % arrival)
	var ways_out := 0
	for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		if dm.is_walkable(arrival + d):
			ways_out += 1
	_check(ways_out == 1, "arrival walled in: %d way out, the bridge" % ways_out)

	# A bridge cell crossed consumes one disarray move.
	var first := Vector3i(1, 2, 2)
	var bridge = null
	for m in dm.mechanisms_at(first):
		if m.has_method("engage"):
			bridge = m
	if bridge == null:
		_check(false, "bridge mechanism at %s" % first)
		return
	bridge.engage(Vector3i(0, 0, 1), false)
	scene._active_bridge = bridge
	scene._bridge_from = first
	scene._bridge_dir = Vector3i(0, 0, 1)
	player.affliction.add_disarray(5)
	var before: int = player.affliction.remaining_disarray()
	scene._advance_bridge_cell(player)
	var after: int = player.affliction.remaining_disarray()
	_check(after == before - 1, "a bridge cell counts disarray down (%d -> %d)" % [before, after])


## The design doc's rival rules for narrow bridges: a simplified balance test rolled at creation,
## a fall to the floor below with damage, devitalisation on the map, and two rivals meeting on a
## plank both falling, onto two distinct cells.
func _check_rival_on_bridge(dm) -> void:
	var rivals: Array = dm.rivals()
	_check(rivals.size() == 1, "%d rival on the map" % rivals.size())
	if rivals.is_empty():
		return
	var r = rivals[0]
	_check(
		r.bridge_fall_chance >= 0.01 and r.bridge_fall_chance <= 0.02,
		"fall chance rolled inside 1-2%% (%.2f%%)" % (r.bridge_fall_chance * 100.0)
	)
	_check(r.den == r.max_den, "map DEN full at the start (%d)" % r.den)

	# Falling off a plank: lands at the bottom of the ravine and takes 2 storeys' worth.
	var plank := Vector3i(1, 2, 4)
	_check(dm.is_narrow_bridge(plank), "cell %s recognised as a plank" % plank)
	dm.release(r.cell)
	dm.reserve(plank, r)
	r.cell = plank
	var den_before: int = r.den
	var alive: bool = r.fall_down(plank)
	var expected: int = dm.fall_damage(2)  # the design doc: 2 height units is 10 DEN
	_check(alive and r.cell.y == 0, "the rival falls to the bottom of the ravine (%s)" % r.cell)
	_check(
		den_before - r.den == expected,
		"rival fall damage is %d DEN over 2 storeys (%d -> %d)" % [expected, den_before, r.den]
	)

	# Devitalised by a fall: dissolved on the map, with no encounter.
	r.apply_map_damage(r.max_den)
	await get_tree().process_frame
	_check(
		dm.rivals().is_empty() and not is_instance_valid(r),
		"a rival devitalised by a fall is dissolved, with no encounter"
	)

	# Two rivals meeting on a plank: both fall, onto two distinct cells.
	var a = ScenarioCatalog._spawn_rival(dm, &"ravbak", Vector3i(1, 2, 3))
	var b = ScenarioCatalog._spawn_rival(dm, &"ravbak", Vector3i(1, 2, 5))
	await get_tree().process_frame
	b._collide_with_rival(Vector3i(1, 2, 3), a)
	_check(a.cell.y == 0 and b.cell.y == 0, "both rivals fall (%s / %s)" % [a.cell, b.cell])
	_check(a.cell != b.cell, "they land on two distinct cells")

	# Chasing a FLOOR CHANGE: the player climbs back to the start, and the rival follows by the two
	# flights of stairs — a free route, so no hesitation, unlike a fall.
	var chaser = ScenarioCatalog._spawn_rival(dm, &"ravbak", Vector3i(2, 0, 5))
	await get_tree().process_frame
	chaser.move_duration = 0.0
	var top := Vector3i(3, 2, 0)
	chaser.witness_player_level_change(Vector3i(3, 0, 5), top)
	var turns_used := 0
	for i in range(20):
		chaser.take_turn(top)
		for f in range(3):
			await get_tree().process_frame
		turns_used += 1
		if chaser.cell.y == top.y:
			break
	_check(
		chaser.cell.y == top.y,
		(
			"a rival follows the player between storeys by the stairs (%s in %d turns)"
			% [chaser.cell, turns_used]
		)
	)


## Multi-storey: you walk UNDER the tiers, the design doc's fall scale holds at all four heights,
## and both shapes of elevator make the round trip with their rider.
func _check_stairs(dm, player) -> void:
	# The pillar: cell (1,0,8) was removed from storey 0, so it is rendered as a wall block — and
	# that wall carries the floor of the cell above, with no extra slab.
	var pillar := Vector3i(1, 0, 8)
	var carried := pillar + Vector3i.UP
	var walls: Dictionary = dm.derive_wall_cells()
	_check(walls.has(pillar), "removed cell rendered as a wall block (the pillar)")
	_check(not dm.is_floor(pillar) and dm.is_floor(carried), "walkable floor resting on the pillar")
	_check(
		dm.cell_to_world(carried).y == dm.cell_to_world(pillar).y + dm.CELL_SIZE,
		"the carried floor sits exactly at the wall's top face"
	)

	_check_guardrails(dm)

	var under := Vector3i(3, 0, 6)
	var above := Vector3i(3, 1, 6)
	_check(dm.is_walkable(under), "walkable cell under the tier")
	_check(dm.is_floor(above), "a tier above that cell")
	var headroom: float = dm.cell_to_world(above).y - dm.FLOOR_THICKNESS - dm.cell_to_world(under).y
	_check(headroom > dm.EYE_HEIGHT, "headroom under the ceiling = %.2f m, above eyes" % headroom)
	var levels := 0
	for y in range(0, 6):
		if dm.is_floor(Vector3i(6, y, 12)):
			levels += 1
	_check(levels == 5, "%d storeys stacked" % levels)

	# ONE STAIRCASE per tier: the fallback route. An elevator stays where it was left, so without a
	# flight doubling each storey change, a fall could make the top permanently unreachable.
	var by_level := {}
	for m in dm.get_children():
		if not m.has_method("stairs_destination") or m.level_delta <= 0:
			continue
		var from: Vector3i = m.level_link_from()
		var to: Vector3i = m.level_link_to()
		if dm.is_walkable(from) and dm.is_floor(to) and to.y == from.y + 1:
			by_level[from.y] = true
	var missing := []
	for y in range(0, 4):
		if not by_level.has(y):
			missing.append(y)
	_check(
		missing.is_empty(), "a walkable flight for every tier 0-1-2-3-4 (missing: %s)" % [missing]
	)

	# The design doc's scale: "2+ height units -> 10 damage, plus 5 per additional unit".
	for pair in [[1, 0], [2, 10], [3, 15], [4, 20]]:
		_check(
			dm.fall_damage(pair[0]) == pair[1],
			"fall of %d unit(s): %d DEN (%d)" % [pair[0], pair[1], dm.fall_damage(pair[0])]
		)

	# All four heights have to be reachable: on the EAST column (x = 6) nothing stops a fall before
	# storey 0, so stepping off tier y should fall y units.
	for y in range(1, 5):
		var landing: Vector3i = dm.fall_landing(Vector3i(7, y, 8))
		_check(
			landing == Vector3i(7, 0, 8),
			"stepping off tier %d on the east side is a %d-unit fall (%s)" % [y, y, landing]
		)
	# On the WEST side each tier overhangs the next: a single unit, and so no damage.
	_check(
		dm.fall_landing(Vector3i(1, 2, 8)) == Vector3i(1, 1, 8),
		"stepping off a tier on the west side is a 1-unit fall, painless"
	)

	# Elevators: one vertical, one on a complex route with segments along all three axes.
	var lifts := []
	for m in dm.get_children():
		if m.has_method("ride"):
			lifts.append(m)
	_check(lifts.size() == 2, "%d elevators" % lifts.size())
	var winding = null
	for m in lifts:
		if m.path.size() == 1:
			_check(m.far_end().y != m.cell.y, "elevator %s: vertical route" % m.cell)
		elif m.path.size() > 1:
			winding = m
	if winding == null:
		_check(false, "one elevator on a complex route")
	else:
		var axes := {}
		var prev: Vector3i = winding.cell
		for wp in winding.path:
			var d: Vector3i = wp - prev
			if d.x != 0:
				axes["x"] = true
			if d.y != 0:
				axes["y"] = true
			if d.z != 0:
				axes["z"] = true
			prev = wp
		_check(
			axes.size() == 3,
			(
				"elevator %s: complex route, %d segments across %d axes"
				% [winding.cell, winding.path.size(), axes.size()]
			)
		)

	# Round trip on each of the two, with the player aboard.
	for lift in lifts:
		lift.segment_duration = 0.0
		lift.rider_segment_duration = 0.0
		var start: Vector3i = lift.cell
		var target: Vector3i = lift.far_end()
		player.teleport_to(start)
		dm.notify_entered(start, player)
		await get_tree().process_frame
		_check(
			player.cell == target and lift.cell == target,
			"%s -> %s: the platform carries its rider (%s)" % [start, target, player.cell]
		)
		dm.notify_entered(lift.cell, player)
		await get_tree().process_frame
		_check(
			player.cell == start and lift.cell == start,
			"stepping back on returns it to its starting point (%s)" % player.cell
		)
