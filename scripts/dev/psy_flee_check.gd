## Headless check of fleeing above the first PSY rung: the group stays, the duo lands only 2 to 3
## walkable steps off on a tile with nothing on it, turned to face the group, and that group's
## Talk chance is lower from then on. At the rung itself, nothing of it applies.
##
## Run with: Godot --headless --path . res://scenes/dev/psy_flee_check.tscn
## As a start scene rather than --script; see geometry_check.gd.
extends Node

const ScenarioCatalog := preload("res://scripts/dev/scenario_catalog.gd")
const EXPLORATION := preload("res://scenes/exploration/exploration.tscn")
const RIVAL_SCENE := preload("res://scenes/exploration/rival/rival.tscn")
const RivalMember := preload("res://scripts/exploration/rival_member.gd")

## The "movement" scenario: an open 7 x 9 room with pillars, entered at (3, 0, 0).
const START := Vector3i(3, 0, 0)
const NEXT_TO_START := Vector3i(3, 0, 1)

## Runs of a flight: the landing tile is drawn at random, so one run proves little.
const FLIGHTS := 20

var _fails: Array[String] = []


## Plays queued actions, then passes.
class Player:
	extends EncounterAgent
	var queued: Array = []

	func decide(individual: EncounterIndividual, _manager: EncounterManager) -> EncounterAction:
		if not queued.is_empty():
			return queued.pop_front()
		return EncounterAction.of_kind(EncounterAction.Kind.PASS, [individual])


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
	await _check_flight()
	await _check_talk_malus()
	print("")
	if _fails.is_empty():
		print("ALL OK")
	else:
		print("FAILURES: %s" % [_fails])
	get_tree().quit(0 if _fails.is_empty() else 1)


func _spawn_group(dm, tile: Vector3i) -> Node:
	var group = RIVAL_SCENE.instantiate()
	group.members.append(RivalMember.new(&"ravbak", 60, 40))
	group.position = dm.tile_to_world(tile)
	dm.add_child(group)
	await get_tree().process_frame
	return group


## One flight at the given PSY score; returns the group that was fled from.
func _flee(scene, player, dm, psy: int) -> Node:
	GameSession.psy_score = psy
	player.teleport_to(START)
	var g = await _spawn_group(dm, NEXT_TO_START)
	scene._pending_rival = g
	scene._on_encounter_finished(&"fled", [{"den": 33, "eth": 20, "outcome": &"stayed"}])
	await get_tree().process_frame
	return g


func _check_flight() -> void:
	print("[fleeing, by PSY]")
	ScenarioCatalog.selected_id = &"movement"
	var scene = EXPLORATION.instantiate()
	get_tree().root.add_child(scene)
	await get_tree().process_frame
	var dm = scene.get_node("DungeonManager")
	var player = scene.get_node("Player")
	var balance := BalanceData.current()
	var off_range: Array = []
	var not_free: Array = []
	var not_facing: Array = []
	var group_issues: Array = []
	for i in FLIGHTS:
		var g = await _flee(scene, player, dm, balance.psy_rung_1 + 1)
		var reach := balance.psy_flee_distance_max
		var steps: Dictionary = dm.tile_search.walking_distances(START, reach)
		var walked: int = steps.get(player.tile, -1)
		if walked < balance.psy_flee_distance_min or walked > reach:
			off_range.append("%s (%d steps)" % [player.tile, walked])
		if not dm.mechanisms_at(player.tile).is_empty() or dm.occupant_at(player.tile) != null:
			not_free.append(str(player.tile))
		# The heading must point along the larger gap to the group.
		var gap: Vector3i = g.tile - player.tile
		var want := Vector3i(0, 0, signi(gap.z))
		if absi(gap.x) > absi(gap.z):
			want = Vector3i(signi(gap.x), 0, 0)
		if player.facing_delta() != want:
			not_facing.append("%s facing %s, wanted %s" % [player.tile, player.facing_delta(), want])
		if not is_instance_valid(g) or g.tile != NEXT_TO_START:
			group_issues.append("the group moved or is gone")
		elif absf(g.members[0].talk_malus - balance.psy_flee_talk_malus) > 0.0001:
			group_issues.append("malus %f" % g.members[0].talk_malus)
		else:
			var state: Dictionary = g.encounter_states()[0]
			if absf(float(state.get("talk_malus", 0.0)) - balance.psy_flee_talk_malus) > 0.0001:
				group_issues.append("malus missing from the encounter state")
		if is_instance_valid(g):
			g.remove_from_dungeon()
		await get_tree().process_frame
	_check(off_range.is_empty(), "above rung 1 the duo lands 2 to 3 steps off %s" % [off_range])
	_check(not_free.is_empty(), "...on a tile with no mechanism and nobody on it %s" % [not_free])
	_check(not_facing.is_empty(), "...facing the group %s" % [not_facing.slice(0, 3)])
	_check(group_issues.is_empty(), "...the group stays put and talks less %s" % [group_issues.slice(0, 3)])

	# At the rung itself (strictly above is needed) nothing of this applies.
	var near: Array = []
	var malus: Array = []
	for i in FLIGHTS:
		var g = await _flee(scene, player, dm, balance.psy_rung_1)
		var steps: Dictionary = dm.tile_search.walking_distances(START, balance.flee_distance_max)
		var walked: int = steps.get(player.tile, -1)
		if walked < balance.flee_distance_min:
			near.append("%s (%d)" % [player.tile, walked])
		if g.members[0].talk_malus != 0.0:
			malus.append("malus")
		g.remove_from_dungeon()
		await get_tree().process_frame
	_check(near.is_empty(), "at PSY %d the flight is the usual 3 to 5 %s" % [balance.psy_rung_1, near])
	_check(malus.is_empty(), "...and the group's Talk chance is untouched")
	GameSession.psy_score = 0
	scene.queue_free()
	await get_tree().process_frame


## One Talk from a player at a rival with the given Talk chance and malus.
func _talk(chance: float, malus: float, seed: int) -> bool:
	var p := EncounterManager.make_individual(&"kalilk", true)
	var r := EncounterManager.make_individual(&"ravbak", false)
	r.species.talker_chance = chance
	r.talk_chance_malus = malus
	var m := EncounterManager.new()
	m.setup([p], [r], seed)
	m.timeline.order = [p, r]
	for f in [p, r]:
		m.set_agent(f, Player.new())
	(m.agent_for(p) as Player).queued = [EncounterAction.of_kind(EncounterAction.Kind.TALK, [r])]
	await m.run(1)
	var effective := m.last_talk_effective
	m.free()
	return effective


func _check_talk_malus() -> void:
	print("[the Talk chance]")
	var plain: bool = await _talk(1.0, 0.0, 20261022)
	var whole: bool = await _talk(1.0, 1.0, 20261022)
	_check(plain, "a sure Talk works with no malus")
	_check(not whole, "...and fails once the whole chance is taken off")

	# 10 % less is relative: from a 50 % chance, 45 %.
	var seen := 0
	var trials := 400
	for i in trials:
		var ok: bool = await _talk(0.5, 0.1, 1000 + i)
		if ok:
			seen += 1
	var rate := float(seen) / float(trials)
	_check(rate > 0.37 and rate < 0.53, "a 50 %% Talk with a 10 %% malus works about 45 %% (%.2f)" % rate)
