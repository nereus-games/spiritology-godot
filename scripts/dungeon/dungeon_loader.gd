## Builds a playable dungeon from its map files: fills a [DungeonManager]'s layout, safe areas and
## teleport rules, places the mechanisms, and says where the player starts and which way they face.
##
## The counterpart of [method ScenarioCatalog.build] for a dungeon that is data rather than code,
## and the only thing besides it that puts mechanisms on a layout. What the plan names a `kind`
## becomes a mechanism script here, with its properties translated into the script's own.
##
## What is not built yet, said out loud rather than dropped silently:
##  - SCENERY (columns, stone trees, a submarine): cosmetic, not drawn.
##  - The spawn rules of `rules.cfg` other than the groups at entry, which come from the dungeon's
##    [DungeonConfig] when it has one.
##
## No `class_name` (the CLI class-cache trap): referenced by `preload`. References the autoloads.
extends RefCounted

const Kinds := preload("res://scripts/dungeon/dungeon_kinds.gd")
const Parser := preload("res://scripts/dungeon/dungeon_map_parser.gd")
const Validator := preload("res://scripts/dungeon/dungeon_validator.gd")
const ScenarioCatalog := preload("res://scripts/dev/scenario_catalog.gd")

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

## Where the player looks on arriving, as a rotation about the vertical axis from the default,
## which faces north (-z).
const YAW := {"N": 0.0, "W": PI / 2.0, "S": PI, "E": -PI / 2.0}


## Builds `slug` into `dm`. Returns `{start: Vector3i, yaw: float, plan, issues: Array}`: the
## entrance, the angle to face, the plan that was read, and what the validator made of it (the
## dungeon is built all the same: a fault is reported, not a reason to refuse to play).
static func build(slug: StringName, dm) -> Dictionary:
	return build_plan(Parser.load_slug(slug), dm, GameData.dungeon(slug))


## [method build] for a plan already read, with the [DungeonConfig] it runs under, or null.
static func build_plan(plan, dm, config: DungeonConfig = null) -> Dictionary:
	ScenarioCatalog.reset_session()
	var issues: Array = Validator.new().validate(plan, config)
	for issue in issues:
		if issue["severity"] == "error":
			push_warning("[DungeonLoader] %s: %s" % [plan.slug, Validator.format_issue(issue)])

	_lay_out(plan, dm)
	_place_mechanisms(plan, dm)
	dm.safe_areas.mark(plan.tiles_with_tag("safe").keys())
	dm.tile_search.forbid_teleport_to(plan.tiles_with_tag("no_teleport").keys())
	dm.config = _config_for(config, plan)

	var start: Vector3i = plan.entrance
	if not plan.has_entrance:
		push_warning("[DungeonLoader] %s has no entrance: starting on its first floor tile." % plan.slug)
		start = plan.floor_tiles.keys()[0] if not plan.floor_tiles.is_empty() else Vector3i.ZERO
	dm.layout.set_entrance(start)
	for exit in plan.exits:
		dm.layout.add_exit(exit)

	var facing: Vector3i = plan.tile_props.get(start, {}).get("facing", Vector3i(0, 0, 1))
	return {"start": start, "yaw": _yaw_of(facing), "plan": plan, "issues": issues}


static func _yaw_of(facing: Vector3i) -> float:
	for key in Kinds.DIRECTIONS:
		if Kinds.DIRECTIONS[key] == facing:
			return YAW[key]
	return PI


# --------------------------------------------------------------------------
# The layout
# --------------------------------------------------------------------------


static func _lay_out(plan, dm) -> void:
	for tile in plan.floor_tiles:
		dm.layout.add_floor(tile)
	for tile in plan.pit_tiles:
		dm.layout.mark_pit(tile)
	for tile in plan.hole_tiles:
		dm.layout.mark_hole(tile)
	for tile in plan.wall_tiles:
		dm.layout.declare_wall(tile)
	for tile in plan.water_tiles:
		dm.layout.mark_water(tile)
	# `[water] emerge = "F25@0"`: where whoever falls into the water comes back up.
	var emerge = Kinds.parse_tile(String(plan.rule("water", "emerge", "")), 0)
	if emerge != null:
		dm.layout.set_emerge_tile(emerge)


## The dungeon's rules: its [DungeonConfig] when it has one, with the map's rival spawn points
## filled in where the config names none. A copy, so that the shared resource is left alone.
## Null when there is no config: no group appears.
static func _config_for(shared: DungeonConfig, plan) -> DungeonConfig:
	if shared == null:
		return null
	var config: DungeonConfig = shared.duplicate()
	if config.spawn_points.is_empty():
		var points: Array[Vector3i] = []
		for p in plan.placements:
			if p["kind"] == &"rival_spawn":
				points.append(p["tile"])
		config.spawn_points = points
	return config


# --------------------------------------------------------------------------
# The mechanisms
# --------------------------------------------------------------------------


static func _place_mechanisms(plan, dm) -> void:
	var lifts: Dictionary = {}  # tile -> Elevator, to link them once every one exists
	for p in plan.placements:
		var tile: Vector3i = p["tile"]
		var props: Dictionary = p["props"]
		match p["kind"]:
			&"trap":
				var set := {}
				if props.has("type"):
					set["kind"] = Trap.Kind[String(props["type"]).to_upper()]
				_copy(props, set, ["reactivates", "revealed", "poison_per_turn", "poison_turns"])
				_copy(props, set, ["disarray_min", "disarray_max"])
				ScenarioCatalog.place(dm, Trap, tile, set)
			&"chest":
				var set := {}
				if props.has("trapped"):
					set["is_trap"] = props["trapped"]
				if props.has("loot"):
					set["fixed_loot"] = _names(props["loot"])
				_copy(props, set, ["loot_min", "loot_max", "revealed"])
				ScenarioCatalog.place(dm, Chest, tile, set)
			&"gate":
				ScenarioCatalog.place(dm, Gateway, tile, _gate_props(props))
			&"stairs":
				var delta := 1 if props.get("dir", "up") == "up" else -1
				ScenarioCatalog.place(
					dm, Stairs, tile, {"level_delta": delta, "face_dir": props.get("face", Vector3i(0, 0, 1))}
				)
			&"lift":
				var path: Array[Vector3i] = []
				path.assign(props.get("path", []))
				lifts[tile] = ScenarioCatalog.place(dm, Elevator, tile, {"path": path})
			&"bridge":
				ScenarioCatalog.spawn_plank(dm, tile, _runs_along_x(plan, tile))
				ScenarioCatalog.place(dm, NarrowBridge, tile)
			&"guardrail":
				ScenarioCatalog.place(dm, Guardrail, tile, {"edge_dir": props.get("edge", Vector3i(0, 0, 1))})
			&"crumbly":
				ScenarioCatalog.place(dm, CrumblyGround, tile, _loot_pool(props))
			&"litter":
				ScenarioCatalog.place(dm, Litter, tile, _loot_pool(props))
			&"crystal":
				ScenarioCatalog.place(dm, RefreshCrystal, tile)
			&"dieverting":
				ScenarioCatalog.place(dm, Dieverting, tile)
			&"cracked_wall":
				ScenarioCatalog.place(dm, CrackedWall, tile)
			&"decor":
				var set := {}
				if props.has("type"):
					set["decor_type"] = ExaminableDecor.DecorType[String(props["type"]).to_upper()]
				ScenarioCatalog.place(dm, ExaminableDecor, tile, set)
			_:
				pass  # spawn points feed the config; scenery is not drawn yet
	for tile in lifts:
		var wanted: Array = _plan_of(plan, tile).get("linked", [])
		var others: Array = []
		for t in wanted:
			if lifts.has(t):
				others.append(lifts[t])
		lifts[tile].linked = others


static func _plan_of(plan, tile: Vector3i) -> Dictionary:
	for p in plan.placements_at(tile):
		if p["kind"] == &"lift":
			return p["props"]
	return {}


static func _gate_props(props: Dictionary) -> Dictionary:
	var set := {"kind": Gateway.Kind[String(props.get("type", "automated")).to_upper()]}
	if props.has("edge"):
		set["edge_dir"] = props["edge"]
	if props.has("arrival"):
		set["arrival_tile"] = props["arrival"]
	if props.has("two_sided"):
		set["two_sided"] = props["two_sided"]
	if props.has("currency"):
		set["cost_currency"] = StringName(props["currency"])
	if props.has("tier"):
		set["cost_tier"] = Gateway.CostTier[String(props["tier"]).to_upper()]
	if props.has("meditations"):
		set["meditations_required"] = props["meditations"]
	return set


static func _loot_pool(props: Dictionary) -> Dictionary:
	return {"loot_pool": _names(props["loot"])} if props.has("loot") else {}


static func _copy(from: Dictionary, to: Dictionary, keys: Array) -> void:
	for key in keys:
		if from.has(key):
			to[key] = from[key]


static func _names(list: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	for item in list:
		out.append(StringName(item))
	return out


## A plank lies along the bridge: east-west when the tiles beside it east and west are floor and
## the ones north and south are not.
static func _runs_along_x(plan, tile: Vector3i) -> bool:
	var ew: bool = plan.is_floor(tile + Vector3i(1, 0, 0)) or plan.is_floor(tile + Vector3i(-1, 0, 0))
	var ns: bool = plan.is_floor(tile + Vector3i(0, 0, 1)) or plan.is_floor(tile + Vector3i(0, 0, -1))
	return ew and not ns
