## Headless check of the abilities that were still marked `# @unimplemented`, as far as each one
## can be settled today. Cranny Crossing is an exploration ability whose mechanic lives in the
## cracked wall; its encounter script must stay inert and must never reach an encounter menu.
## Anti-Stress, Avoidant Gaze and Distancing have no usable mechanic in the design doc yet, so
## they keep their marker; a case below pins that they still carry it, so that implementing one
## cannot go unnoticed here.
##
## Run with: Godot --headless --path . res://scenes/dev/unimplemented_a_check.tscn
## As a start scene rather than --script; see geometry_check.gd.
extends Node

const ABILITY_DIR := "res://data/abilities/"
const SCRIPT_DIR := "res://scripts/encounter/effects/abilities/"

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
	await _check_cranny_crossing()
	_check_markers()
	print("")
	if _fails.is_empty():
		print("ALL OK")
	else:
		print("FAILURES: %s" % [_fails])
	get_tree().quit(0 if _fails.is_empty() else 1)


func _ability(id: StringName) -> AbilityData:
	return load(ABILITY_DIR + "%s.tres" % id)


## Two players and two rivals; everyone passes unless told otherwise. The caller frees it.
func _encounter() -> EncounterManager:
	var all: Array = []
	for id in [&"kalilk", &"fliritus"]:
		all.append(EncounterManager.make_individual(id, true))
	for id in [&"ravbak", &"skorpis"]:
		all.append(EncounterManager.make_individual(id, false))
	var m := EncounterManager.new()
	m.setup([all[0], all[1]], [all[2], all[3]], 20261022)
	m.timeline.order = all.duplicate()
	for f in all:
		m.set_agent(f, Player.new())
	return m


func _snapshot(m: EncounterManager) -> Array:
	var out: Array = []
	for f in m.players + m.rivals:
		out.append([f.den, f.eth])
	return out


func _check_cranny_crossing() -> void:
	print("[cranny crossing]")
	var ability := _ability(&"cranny_crossing")
	var m := _encounter()
	var p0: EncounterIndividual = m.players[0]
	p0.ability_ids.append(&"cranny_crossing")
	_check(
		ability.type == GameEnums.AbilityType.EXPLORATION,
		"it is an exploration ability in the data"
	)
	_check(not (ability in m.encounter_abilities(p0)), "an encounter menu never offers it")
	(m.agent_for(p0) as Player).queued = [EncounterAction.use_ability(ability, [p0])]
	var before := _snapshot(m)
	await m.run(1)
	_check(_snapshot(m) == before, "were it played, nobody's DEN or ETH moves")
	m.free()


## The three abilities with no mechanic in the design doc keep their marker. Not a judgement on
## the code: when one is implemented this goes red, and the case should then be replaced by a
## real one.
func _check_markers() -> void:
	print("[still unimplemented]")
	for id in [&"anti_stress", &"avoidant_gaze", &"distancing"]:
		var line := FileAccess.get_file_as_string(SCRIPT_DIR + "%s.gd" % id).get_slice("\n", 0)
		_check(line == "# @unimplemented", "%s still carries its marker" % id)
	var line := FileAccess.get_file_as_string(SCRIPT_DIR + "cranny_crossing.gd").get_slice("\n", 0)
	_check(line != "# @unimplemented", "cranny_crossing no longer does")
