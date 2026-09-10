## Examinable decor.
##
## From the design doc ("Walls + Decors"). 10-15% of encyclopaedia infos come not from encounters
## but from Examining dedicated pieces of decor, which hand out a random info about a
## spirimonster from a pool specific to the decor's TYPE. Examinable once per visit. (Litter and
## Crumbly Grounds have mechanisms of their own; this covers Gooey Marks, Posters and Scratch
## Marks.) At a high PSY score the interaction has a chance of spawning rivals nearby.
##
## No `class_name`: `extends` by path. References the GameSession autoload.
extends "res://scripts/exploration/mechanisms/dungeon_mechanism.gd"

const ExplorationAction := preload("res://scripts/exploration/exploration_action.gd")

enum DecorType { GOOEY_MARKS, POSTERS, SCRATCH_MARKS }

## Spirimonster pools per decor type ("Walls + Decors").
##
## ## TODO: the design doc also lists "mazir" among the gooey marks, but that species has no
## page, and therefore no `data/species/mazir.tres`. It was drawn without ever giving anything.
## Put it back once the species exists.
const POOLS := {
	DecorType.GOOEY_MARKS:
	[
		&"kurkab",
		&"malcouli",
		&"senskor",
		&"spodra",
		&"sadakbia",
		&"fonechal",
		&"kalilk",
		&"sopiark",
	],
	DecorType.POSTERS:
	[
		&"jezal",
		&"zuk",
		&"fopin",
		&"oleni",
		&"erzelak",
		&"ravbak",
		&"gelmi",
		&"niyat",
	],
	DecorType.SCRATCH_MARKS:
	[
		&"yadol",
		&"gaiaz",
		&"draka",
		&"kalilk",
		&"razel",
		&"erdouss",
		&"vernal",
	],
}

@export var decor_type: DecorType = DecorType.POSTERS

var _examined := false


func has_been_examined() -> bool:
	return _examined


## Decor already examined: nothing more to get out of it this visit.
func is_spent() -> bool:
	return _examined


## Examine, available from an adjacent cell, once per visit.
func on_adjacent_actions(who: Node, _facing: Vector3i) -> Array:
	if _examined:
		return []
	return [
		ExplorationAction.new(&"examine", "UI_ACTION_EXAMINE", Callable(self, "examine").bind(who))
	]


## Examine: hands out an encyclopaedia info about a spirimonster from this decor type's pool.
func examine(_who: Node) -> void:
	if _examined:
		return
	_examined = true
	# Decor that has been read is greyed out but not flattened: it is a wall element, and
	# squashing it to the floor would make no sense.
	_grey_marker()
	var pool: Array = POOLS[decor_type]
	if not pool.is_empty():
		GameSession.award_ifp(pool[randi() % pool.size()], GameEnums.IfpAction.EXAMINE_DECOR)
	# ## TODO: at a high PSY, a chance to spawn one or more rivals nearby, but not on the
	## player's cell. The design doc leaves the "how much?" threshold unquantified; this needs a
	## spawn system.


## Persistence between visits: unexamined decor keeps its place, examined decor disappears and
## is replaced elsewhere, which the dungeon level handles. Here the state is simply kept.
func reset_between_visits() -> void:
	pass


func _spawn_visual() -> void:
	_add_marker(Color(0.7, 0.3, 0.7), 0.65, 0.3)  # thin magenta decor: a poster or a mark
