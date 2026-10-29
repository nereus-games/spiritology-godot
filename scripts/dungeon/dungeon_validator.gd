## Checks a [DungeonPlan] against the design doc's level-design rules, and reports every fault
## at once rather than the first.
##
## An issue is a Dictionary: `severity` ("error" or "warning"), `code`, `tile` (a Vector3i, or
## null), `source` (file and line, when the fault comes from a file) and `args`. [method message]
## gives the English line the command-line tool prints. The editor will show the same issues
## through translation keys of its own.
##
## Reachability is walked forward from the entrance, through what the game allows: steps between
## floor tiles not barred by a guardrail, stairs, lifts, teleport gates, cracked walls (the
## ability is taken as available) and falls — a tile that can only be reached by falling is
## still reached. A region nothing reaches is an ERROR unless the notes say otherwise: tag a
## tile or a zone `unreachable_ok`.
##
## No `class_name` (the CLI class-cache trap): referenced by `preload`.
extends RefCounted

const Kinds := preload("res://scripts/dungeon/dungeon_kinds.gd")

const NEIGHBOURS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)
]

const MESSAGES := {
	"NO_DIRECTORY": "no directory for this dungeon: %s",
	"NO_MAP_FILES": "no floor_*.map file in %s",
	"UNKNOWN_SECTION": "unknown section [%s]",
	"LINE_OUTSIDE_SECTION": "line outside any section: %s",
	"MISSING_FLOOR_Y": "no `y = N` in [floor]",
	"BAD_LINE": "cannot read this line: %s",
	"BAD_TILE": "not a tile: %s",
	"BAD_VALUE": "bad value: %s",
	"UNCLOSED_QUOTE": "unclosed quote: %s",
	"LEGEND_CORE_CHAR": "'%s' is a grid character and cannot be redefined",
	"UNKNOWN_KIND": "unknown kind '%s'",
	"UNKNOWN_CHAR": "'%s' is not in the legend",
	"DUPLICATE_ENTRANCE": "a second entrance (E)",
	"NO_ENTRANCE": "the dungeon has no entrance (E)",
	"UNKNOWN_PROP": "kind '%s' has no property '%s' (use custom.<name> for a special case)",
	"ASSET_MISSING": "asset does not exist: %s",
	"BOTTOMLESS_HOLE": "a hole with nothing below it",
	"STAIRS_APPROACH": "the tile before the stairs is not floor",
	"STAIRS_DESTINATION": "the stairs lead to %s, which is not floor",
	"STAIRS_ABOVE": "the tile directly above the stairs is floor",
	"STAIRS_FACE": "stairs need `face=N|E|S|W`",
	"BRIDGE_NOT_PIT": "a bridge plank on a tile that is not a pit",
	"BRIDGE_NO_GAP": "a bridge over nothing: no floor below",
	"BRIDGE_NO_WAY_BACK": "after a fall from this bridge there is no way back to the entrance",
	"LIFT_NO_PATH": "a lift with no `path`",
	"LIFT_END_NOT_FLOOR": "the lift's far end %s is not floor",
	"GATE_NO_ARRIVAL": "a teleport gate with no `arrival`",
	"GATE_ARRIVAL_NOT_FLOOR": "the teleport gate arrives on %s, which is not floor",
	"GATE_NO_EDGE": "a gate or guardrail needs `edge=N|E|S|W`",
	"TELEPORT_INTO_RESTRICTED": "a teleport lands on %s, in a no_teleport zone",
	"SAFE_NO_FLOOR": "a safe tile with no floor",
	"SAFE_HAZARD": "a hazard (%s) in a safe area",
	"SAFE_LEDGE": "a safe tile has an unrailed ledge towards %s",
	"SPAWN_NOT_FLOOR": "%s: not a floor tile",
	"SPAWN_IN_SAFE_AREA": "%s: inside a safe area",
	"EXIT_UNREACHABLE": "an exit that cannot be reached from the entrance",
	"UNREACHABLE": "%d floor tile(s) cannot be reached from the entrance (from %s)",
}

var _plan
var _config
var _issues: Array = []
# Directed links that are not a plain step: tile -> Array[Vector3i].
var _links: Dictionary = {}
# Edges (canonical key) -> "block" for a guardrail or a teleport gate.
var _blocked_edges: Dictionary = {}


## All issues for `plan`: the parser's own, then the rules'. `config` is the dungeon's
## [DungeonConfig] when it has one.
func validate(plan, config = null) -> Array:
	_plan = plan
	_config = config
	_issues = plan.issues.duplicate()
	_links.clear()
	_blocked_edges.clear()
	if not plan.has_entrance and not plan.floor_tiles.is_empty():
		_add("error", "NO_ENTRANCE", null)
	_check_props_and_assets()
	_check_holes()
	_index_edges_and_links()
	_check_stairs()
	_check_bridges()
	_check_lifts()
	_check_gates()
	_check_reachability()
	_check_safe_areas()
	_check_config()
	return _issues


## The English line for an issue.
static func message(issue: Dictionary) -> String:
	var text: String = MESSAGES.get(issue["code"], issue["code"])
	var args: Array = issue["args"]
	if args.size() > 0 and text.contains("%"):
		text = text % args
	return text


## "error  floor_00.map:12  (3, 0, 4)  message", one line per issue.
static func format_issue(issue: Dictionary) -> String:
	var where := ""
	if issue["tile"] != null:
		var t: Vector3i = issue["tile"]
		where = "  (%d, %d, %d)" % [t.x, t.y, t.z]
	return "%-7s %s%s  %s" % [issue["severity"], issue["source"], where, message(issue)]


static func error_count(issues: Array) -> int:
	var n := 0
	for i in issues:
		if i["severity"] == "error":
			n += 1
	return n


# --------------------------------------------------------------------------
# Rules
# --------------------------------------------------------------------------


func _check_props_and_assets() -> void:
	for p in _plan.placements:
		for name in p["props"]:
			if Kinds.prop_type(p["kind"], name) == "":
				_add("warning", "UNKNOWN_PROP", p["tile"], [p["kind"], name], p["source"])
		_check_asset(p["props"], p["tile"], p["source"])
	for tile in _plan.tile_props:
		_check_asset(_plan.tile_props[tile], tile, "")


func _check_asset(props: Dictionary, tile: Vector3i, source: String) -> void:
	var asset: String = props.get("asset", "")
	if asset != "" and not ResourceLoader.exists(asset):
		_add("error", "ASSET_MISSING", tile, [asset], source)


## A hole nothing catches is a level-design mistake (`TODO(dungeon checker)` in
## `player_controller.gd`).
func _check_holes() -> void:
	for tile in _plan.hole_tiles:
		if _plan.fall_landing(tile) == tile:
			_add("error", "BOTTOMLESS_HOLE", tile)


func _index_edges_and_links() -> void:
	for p in _plan.placements:
		var tile: Vector3i = p["tile"]
		var props: Dictionary = p["props"]
		match p["kind"]:
			&"guardrail":
				if not props.has("edge"):
					_add("error", "GATE_NO_EDGE", tile, [], p["source"])
				else:
					_blocked_edges[_edge_key(tile, tile + props["edge"])] = true
			&"gate":
				if not props.has("edge"):
					_add("error", "GATE_NO_EDGE", tile, [], p["source"])
					continue
				var other: Vector3i = tile + props["edge"]
				if props.get("type", "automated") == "teleport":
					_blocked_edges[_edge_key(tile, other)] = true
					if props.has("arrival"):
						_link(tile, props["arrival"])
						if props.get("two_sided", false):
							_link(other, props["arrival"])
			&"stairs":
				if props.has("face"):
					var dy := 1 if props.get("dir", "up") == "up" else -1
					_link(tile - props["face"], tile + props["face"] + Vector3i(0, dy, 0))
			&"lift":
				var path: Array = props.get("path", [])
				if not path.is_empty():
					_link(tile, path[-1])
					_link(path[-1], tile)
			&"cracked_wall":
				for d in NEIGHBOURS:
					_link(tile - d, tile + d)


func _check_stairs() -> void:
	for p in _plan.placements:
		if p["kind"] != &"stairs":
			continue
		var tile: Vector3i = p["tile"]
		var props: Dictionary = p["props"]
		if not props.has("face"):
			_add("error", "STAIRS_FACE", tile, [], p["source"])
			continue
		var dy := 1 if props.get("dir", "up") == "up" else -1
		var destination: Vector3i = tile + props["face"] + Vector3i(0, dy, 0)
		if not _plan.is_floor(tile - props["face"]):
			_add("error", "STAIRS_APPROACH", tile, [], p["source"])
		if not _plan.is_floor(destination):
			_add("error", "STAIRS_DESTINATION", tile, [destination], p["source"])
		# The block of steps rises a full tile: a floor laid over it would cut straight through.
		if _plan.is_floor(tile + Vector3i(0, 1, 0)):
			_add("error", "STAIRS_ABOVE", tile, [], p["source"])


## A narrow bridge spans a drop, and a fall from it must leave a way back.
func _check_bridges() -> void:
	var back: Dictionary = {}  # landing -> bool, so a long bridge walks once per landing
	for p in _plan.placements:
		if p["kind"] != &"bridge":
			continue
		var tile: Vector3i = p["tile"]
		var landing: Vector3i = _plan.fall_landing(tile)
		if landing == tile:
			_add("error", "BRIDGE_NO_GAP", tile, [], p["source"])
			continue
		if not back.has(landing):
			back[landing] = _plan.has_entrance and _reach(landing).has(_plan.entrance)
		if not back[landing]:
			_add("error", "BRIDGE_NO_WAY_BACK", tile, [], p["source"])


func _check_lifts() -> void:
	for p in _plan.placements:
		if p["kind"] != &"lift":
			continue
		var path: Array = p["props"].get("path", [])
		if path.is_empty():
			_add("error", "LIFT_NO_PATH", p["tile"], [], p["source"])
		elif not _plan.is_floor(path[-1]):
			_add("error", "LIFT_END_NOT_FLOOR", p["tile"], [path[-1]], p["source"])


func _check_gates() -> void:
	var restricted: Dictionary = _plan.tiles_with_tag("no_teleport")
	for p in _plan.placements:
		if p["kind"] != &"gate" or p["props"].get("type", "automated") != "teleport":
			continue
		if not p["props"].has("arrival"):
			_add("error", "GATE_NO_ARRIVAL", p["tile"], [], p["source"])
			continue
		var arrival: Vector3i = p["props"]["arrival"]
		if not _plan.is_floor(arrival):
			_add("error", "GATE_ARRIVAL_NOT_FLOOR", p["tile"], [arrival], p["source"])
		if restricted.has(arrival) or _plan.has_tag(arrival, "no_teleport"):
			_add("error", "TELEPORT_INTO_RESTRICTED", p["tile"], [arrival], p["source"])


## Everything walkable must be reachable, exits included.
func _check_reachability() -> void:
	if not _plan.has_entrance:
		return
	var reached := _reach(_plan.entrance)
	for exit in _plan.exits:
		if not reached.has(exit) and not _plan.has_tag(exit, "unreachable_ok"):
			_add("error", "EXIT_UNREACHABLE", exit)
	# One issue per region rather than one per tile, however large the region.
	var seen: Dictionary = {}
	var tiles: Array = _plan.floor_tiles.keys()
	tiles.sort_custom(_tile_less)
	for start in tiles:
		if reached.has(start) or seen.has(start):
			continue
		var region := _region(start, seen, reached)
		var count := 0
		for t in region:
			if not _plan.has_tag(t, "unreachable_ok"):
				count += 1
		if count > 0:
			_add(
				"error", "UNREACHABLE", start, [count, "%d,%d,%d" % [start.x, start.y, start.z]]
			)


## A safe area holds no hazard and no unrailed ledge (`safe_areas.gd`).
func _check_safe_areas() -> void:
	var safe: Dictionary = _plan.tiles_with_tag("safe")
	for tile in safe:
		if not _plan.is_floor(tile):
			_add("error", "SAFE_NO_FLOOR", tile)
			continue
		for p in _plan.placements_at(tile):
			if Kinds.is_hazard(p["kind"], p["props"]):
				_add("error", "SAFE_HAZARD", tile, [p["kind"]], p["source"])
		for d in NEIGHBOURS:
			var n: Vector3i = tile + d
			if _plan.is_floor(n) or _blocked_edges.has(_edge_key(tile, n)):
				continue
			if _plan.hole_tiles.has(n) or _plan.fall_landing(n) != n:
				_add("error", "SAFE_LEDGE", tile, ["%d,%d,%d" % [n.x, n.y, n.z]])


func _check_config() -> void:
	if _config == null:
		return
	var safe: Dictionary = _plan.tiles_with_tag("safe")
	var points: Array = []
	for point in _config.spawn_points:
		points.append(point)
	for group in _config.fixed_groups:
		if group != null:
			points.append(group.tile)
	for point in points:
		if not _plan.is_floor(point):
			_add("error", "SPAWN_NOT_FLOOR", point, ["%d,%d,%d" % [point.x, point.y, point.z]])
		elif safe.has(point):
			_add("error", "SPAWN_IN_SAFE_AREA", point, ["%d,%d,%d" % [point.x, point.y, point.z]])


# --------------------------------------------------------------------------
# Walking
# --------------------------------------------------------------------------


## Every tile reachable from `start`.
func _reach(start: Vector3i) -> Dictionary:
	var seen := {start: true}
	var queue: Array[Vector3i] = [start]
	var head := 0
	while head < queue.size():
		var tile := queue[head]
		head += 1
		for n in _moves(tile):
			if not seen.has(n):
				seen[n] = true
				queue.append(n)
	return seen


## The unreached floor region containing `start`, ignoring the direction of one-way links, so
## that a pocket is reported once. Marks every tile of it in `seen`; never enters `reached`.
func _region(start: Vector3i, seen: Dictionary, reached: Dictionary) -> Array:
	var out: Array = []
	var queue: Array[Vector3i] = [start]
	seen[start] = true
	var head := 0
	while head < queue.size():
		var tile := queue[head]
		head += 1
		out.append(tile)
		var next: Array[Vector3i] = []
		for d in NEIGHBOURS:
			var m: Vector3i = tile + d
			if _plan.is_floor(m) and not _blocked_edges.has(_edge_key(tile, m)):
				next.append(m)
		for target in _links.get(tile, []):
			next.append(target)
		for m in next:
			if _plan.is_floor(m) and not seen.has(m) and not reached.has(m):
				seen[m] = true
				queue.append(m)
	return out


## Where one move from `tile` can end: a step, a fall off a ledge, or a link.
func _moves(tile: Vector3i) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for d in NEIGHBOURS:
		var n: Vector3i = tile + d
		if _blocked_edges.has(_edge_key(tile, n)):
			continue
		if _plan.is_floor(n):
			out.append(n)
			continue
		# Open air with floor further down: a ledge, and stepping off it is a fall. A staircase
		# or a cracked wall stands on a tile that is not floor but is not air either.
		var landing: Vector3i = _plan.fall_landing(n)
		if landing != n and not _is_solid_mechanism(n):
			out.append(landing)
	for target in _links.get(tile, []):
		if _plan.is_floor(target):
			out.append(target)
	return out


func _is_solid_mechanism(tile: Vector3i) -> bool:
	for p in _plan.placements_at(tile):
		if p["kind"] == &"stairs" or p["kind"] == &"cracked_wall":
			return true
	return false


func _link(from: Vector3i, to: Vector3i) -> void:
	if not _links.has(from):
		_links[from] = []
	_links[from].append(to)


func _edge_key(a: Vector3i, b: Vector3i) -> String:
	if _tile_less(b, a):
		return "%s|%s" % [b, a]
	return "%s|%s" % [a, b]


func _tile_less(a: Vector3i, b: Vector3i) -> bool:
	if a.y != b.y:
		return a.y < b.y
	if a.z != b.z:
		return a.z < b.z
	return a.x < b.x


func _add(severity: String, code: String, tile, args: Array = [], source: String = "") -> void:
	_issues.append(
		{"severity": severity, "code": code, "tile": tile, "source": source, "args": args}
	)
