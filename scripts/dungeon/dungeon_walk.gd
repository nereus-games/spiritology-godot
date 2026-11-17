## A cross-check of the validator against the REAL engine.
##
## The validator decides reachability from a plan, with a model of the moves (steps, stairs, lifts,
## teleport gates, cracked walls, falls). This walks the dungeon the loader BUILT, breadth first
## from the entrance, with no player node, asking only the engine: [method DungeonManager.can_step]
## style queries, the stairs mechanism's own `stairs_destination` and `face_dir`, an elevator's
## `far_end`, a teleport gate's `arrival_tile`, `layout.fall_landing`. Whatever the two disagree
## about is reported: a tile the validator reaches and the engine does not (the validator is too
## generous, or the loader built something else than the plan said) and the other way round.
##
## What the walk assumes, because the engine leaves it to chance or to the player's wallet: a
## locked, meditation or automated gate can be opened (it waits for its turn), a teleport gate is
## open when needed, the cranny ability is available whenever a cracked wall asks for it, a lift
## can be ridden back and forth, litter gets recycled. Traps, rivals and occupancy are ignored.
##
## Water: a step into open water is no move; a fall that ends in water comes up on the layout's
## emerge tile.
##
## Needs a [DungeonManager] already built from the plan, inside the tree (the mechanisms register
## themselves when they enter it). No `class_name` (the CLI class-cache trap): referenced by
## `preload`.
extends RefCounted

const View := preload("res://scripts/dungeon/dungeon_view.gd")
const Validator := preload("res://scripts/dungeon/dungeon_validator.gd")
const Gateway := preload("res://scripts/exploration/mechanisms/gateway.gd")
const CrackedWall := preload("res://scripts/exploration/mechanisms/cracked_wall.gd")

const STEPS: Array[Vector3i] = [
	Vector3i(0, 0, -1), Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(-1, 0, 0)
]
## The validator's issue codes about safe areas, which the engine's `violations()` also covers.
const SAFE_CODES := ["SAFE_NO_FLOOR", "SAFE_HAZARD", "SAFE_LEDGE", "SPAWN_IN_SAFE_AREA"]


## Walks `dm` from its entrance and compares with the validator's model of `plan`.
static func walk(plan, dm) -> Dictionary:
	var start := Vector3i.ZERO
	if dm.layout.has_entrance():
		start = dm.layout.entrance_tile()
	elif not plan.floor_tiles.is_empty():
		start = plan.floor_tiles.keys()[0]
	var lifts: Array = []
	for child in dm.get_children():
		if child.has_method("far_end") and child.has_method("ride"):
			lifts.append(child)
	var reached := {start: true}
	var stood := {start: true}
	var skipped: Array = []
	var queue: Array[Vector3i] = [start]
	var head := 0
	while head < queue.size():
		var tile := queue[head]
		head += 1
		for move in moves(plan, dm, tile, lifts, skipped):
			for passed in move["touched"]:
				reached[passed] = true
			var to: Vector3i = move["to"]
			reached[to] = true
			if not stood.has(to):
				stood[to] = true
				queue.append(to)
	return _compare(plan, dm, start, reached, skipped)


## Every move the engine allows from `tile`: `{to, touched}`, where `touched` lists the tiles
## stepped on on the way that are not where the move ends (a lift's platform). Moves that need
## water the engine cannot model go to `skipped` as `{from, to, why}`.
static func moves(plan, dm, tile: Vector3i, lifts: Array, skipped: Array) -> Array:
	var out: Array = []
	for d in STEPS:
		var n: Vector3i = tile + d
		var gate = Gateway.teleport_gate_between(dm, tile, n)
		if gate != null:
			# A teleport gate never lets anyone across; it sends them to its arrival tile.
			var from_here: bool = (
				tile == gate.tile or (gate.two_sided and tile == gate.tile + gate.edge_dir)
			)
			if from_here and dm.is_floor(gate.arrival_tile) and gate.arrival_tile != tile:
				out.append({"to": gate.arrival_tile, "touched": []})
			continue
		if _barred(dm, tile, n):
			continue
		var stairs = _mechanism(dm, n, "stairs_destination")
		if stairs != null:
			if d == stairs.face_dir:
				var dest: Vector3i = stairs.stairs_destination(tile, d)
				if dm.is_floor(dest):
					out.append({"to": dest, "touched": []})
			continue
		var cracked = _cracked_wall(dm, n)
		if cracked != null:
			if dm.is_walkable(n + d):
				out.append({"to": n + d, "touched": []})
			continue
		if _blocked(dm, n):
			continue
		if not dm.is_floor(n):
			_fall(dm, tile, n, out, skipped)
			continue
		var ride = _mechanism(dm, n, "far_end")
		if ride != null and dm.is_floor(ride.far_end()) and ride.far_end() != n:
			out.append({"to": ride.far_end(), "touched": [n]})
		else:
			out.append({"to": n, "touched": []})
	# On a lift's far platform, riding it back.
	for lift in lifts:
		if lift.far_end() == tile and dm.is_floor(lift.tile):
			out.append({"to": lift.tile, "touched": []})
	# On a plank: a fall off it.
	if dm.is_narrow_bridge(tile):
		_fall(dm, tile, tile, out, skipped)
	return out


## A fall out of `from` into `air` (the same tile for a plank): to the floor below, or, when what
## catches it is water, to the tile the player comes back up on. A step into open water at the
## same level is no move at all, and a fall that ends in water with no emerge tile declared is
## skipped and counted: the validator reports that missing tile, and the engine has nowhere to go.
static func _fall(dm, from: Vector3i, air: Vector3i, out: Array, skipped: Array) -> void:
	if dm.layout.is_open_water(air):
		return
	if dm.layout.drops_into_water(air):
		if dm.layout.has_emerge_tile():
			out.append({"to": dm.layout.emerge_tile(), "touched": []})
		else:
			skipped.append({"from": from, "to": air, "why": "a fall into water, no emerge tile"})
		return
	var landing: Vector3i = dm.layout.fall_landing(air)
	if landing == air:
		return  # a wall, or a bottomless hole: not a way anywhere
	out.append({"to": landing, "touched": []})


## The edge is barred for good: a guardrail. A gate that is merely closed is assumed to open.
static func _barred(dm, a: Vector3i, b: Vector3i) -> bool:
	for m in dm.edge_mechanisms_between(a, b):
		if m.blocks_walk() and not m.has_method("is_teleport"):
			return true
	return false


## A mechanism makes the tile impassable for good: not litter, which Recycle clears.
static func _blocked(dm, tile: Vector3i) -> bool:
	for m in dm.mechanisms_at(tile):
		if m.blocks_walk() and not m.has_method("recycle"):
			return true
	return false


static func _mechanism(dm, tile: Vector3i, method: String):
	for m in dm.mechanisms_at(tile):
		if m.has_method(method):
			return m
	return null


static func _cracked_wall(dm, tile: Vector3i):
	for m in dm.mechanisms_at(tile):
		if m.get_script() == CrackedWall:
			return m
	return null


# --------------------------------------------------------------------------
# Comparison
# --------------------------------------------------------------------------


static func _compare(plan, dm, start: Vector3i, reached: Dictionary, skipped: Array) -> Dictionary:
	var validator := Validator.new()
	var model := validator.reachable_from_entrance(plan)
	var validator_only: Array[Vector3i] = []
	for tile in model:
		if plan.floor_tiles.has(tile) and not reached.has(tile):
			validator_only.append(tile)
	var engine_only: Array[Vector3i] = []
	for tile in reached:
		if not model.has(tile):
			engine_only.append(tile)
	validator_only.sort_custom(_tile_less)
	engine_only.sort_custom(_tile_less)
	var items: Array = []
	for exit in plan.exits:
		items.append(_item("exit", exit, exit, reached, model))
	for kind in [&"chest", &"stairs", &"lift"]:
		for p in View.placements_of(plan, kind):
			var at: Vector3i = p["tile"]
			if kind == &"stairs":
				at = p["tile"] - p["props"].get("face", Vector3i.ZERO)
			items.append(_item(String(kind), p["tile"], at, reached, model))
	var safe_engine: Array[String] = dm.safe_areas.violations()
	var safe_model := 0
	for issue in validator.validate(plan, dm.config):
		if SAFE_CODES.has(issue["code"]):
			safe_model += 1
	var safe_disagree := (safe_engine.size() > 0) != (safe_model > 0)
	var count := validator_only.size() + engine_only.size() + (1 if safe_disagree else 0)
	return {
		"start": start,
		"reached": reached,
		"model": model,
		"validator_only": validator_only,
		"engine_only": engine_only,
		"items": items,
		"skipped": skipped,
		"safe_engine": safe_engine,
		"safe_model": safe_model,
		"safe_disagree": safe_disagree,
		"disagreements": count,
	}


## One thing worth reaching: where it stands, the tile one must reach to use it, and who got there.
static func _item(
	kind: String, tile: Vector3i, at: Vector3i, reached: Dictionary, model: Dictionary
) -> Dictionary:
	return {
		"kind": kind, "tile": tile, "at": at, "engine": reached.has(at), "validator": model.has(at)
	}


static func _tile_less(a: Vector3i, b: Vector3i) -> bool:
	if a.y != b.y:
		return a.y < b.y
	if a.z != b.z:
		return a.z < b.z
	return a.x < b.x


# --------------------------------------------------------------------------
# Report
# --------------------------------------------------------------------------


static func format_report(plan, report: Dictionary) -> String:
	var floor_count := 0
	for tile in report["reached"]:
		if plan.floor_tiles.has(tile):
			floor_count += 1
	var out := "walk %s from %s\n" % [plan.slug, View.tile_name(report["start"], true)]
	out += (
		"engine walk: %d floor tile(s) reached of %d; validator model: %d\n"
		% [floor_count, plan.floor_tiles.size(), report["model"].size()]
	)
	out += "\n%-8s %-8s %-7s %s\n" % ["what", "tile", "engine", "validator"]
	for item in report["items"]:
		var note := ""
		if item["kind"] == "stairs":
			note = "  (approach %s)" % View.tile_name(item["at"], true)
		var line := (
			"%-8s %-8s %-7s %-9s%s"
			% [
				item["kind"],
				View.tile_name(item["tile"], true),
				"yes" if item["engine"] else "NO",
				"yes" if item["validator"] else "NO",
				note
			]
		)
		if item["engine"] != item["validator"]:
			line += "   <-- DISAGREE"
		out += line + "\n"
	out += _tile_list("the validator reaches, the engine does not", report["validator_only"])
	out += _tile_list("the engine reaches, the validator does not", report["engine_only"])
	out += (
		"\nsafe areas: the engine finds %d fault(s), the validator %d"
		% [report["safe_engine"].size(), report["safe_model"]]
	)
	out += "   <-- DISAGREE\n" if report["safe_disagree"] else "\n"
	for line in report["safe_engine"]:
		out += "  engine: %s\n" % line
	var skipped: Array = report["skipped"]
	if not skipped.is_empty():
		out += (
			"\nskipped %d fall(s) into water: no emerge tile is declared\n"
			% skipped.size()
		)
	out += "\nassumed: gates open, the cranny ability is always available, lifts ride both ways\n"
	if report["disagreements"] == 0:
		out += "OK: the engine and the validator agree.\n"
	else:
		out += "DISAGREEMENTS: %d\n" % report["disagreements"]
	return out


static func _tile_list(title: String, tiles: Array) -> String:
	if tiles.is_empty():
		return ""
	var names: Array[String] = []
	for tile in tiles:
		names.append(View.tile_name(tile, true))
		if names.size() >= 40:
			names.append("... and %d more" % (tiles.size() - 40))
			break
	return "\n%s (%d): %s\n" % [title, tiles.size(), ", ".join(names)]
