## Litter: the Examine and Recycle actions.
##
## From the design doc ("Mechanisms / Litter" and "Walls + Decors"). Until it is recycled, litter
## is an OBSTACLE — its cell is impassable — so the player acts on it from an ADJACENT cell. Two
## actions:
##  - Examine hands out one encyclopaedia info about a spirimonster from the associated pool,
##    once per visit;
##  - Recycle gives random objects AND refreshes a random exploration ability, after which the
##    litter becomes ordinary floor: walkable, with no actions left.
##
## No `class_name`: `extends` by path. References the GameSession autoload.
extends "res://scripts/exploration/mechanisms/dungeon_mechanism.gd"

const ExplorationAction := preload("res://scripts/exploration/exploration_action.gd")

## The spirimonsters an Examine on litter can hand out an info about ("Walls + Decors").
##
## ## TODO: the design doc also lists "néarog", which has no species page, and therefore no
## `data/species/néarog.tres`. Leaving it in produced nothing at all: the species was simply
## not found when drawn, with no error. Put it back the day the species exists (see
## data_integrity_check, which now verifies these lists).
const INFO_SPECIES: Array[StringName] = [
	&"firulis",
	&"razel",
	&"kalilk",
	&"vilgane",
	&"zuk",
	&"hibulus",
]

## What a recycle can hand out. Placeholder.
@export var loot_pool: Array[StringName] = [&"rune_stone", &"spade", &"tea_drop"]
@export var loot_min := 1
@export var loot_max := 2

var _recycled := false
var _examined := false


## An obstacle until recycled.
func blocks_walk() -> bool:
	return not _recycled


## Available from an adjacent cell, while not yet recycled.
func on_adjacent_actions(who: Node, _facing: Vector3i) -> Array:
	if _recycled:
		return []
	var actions: Array = []
	if not _examined:
		actions.append(
			ExplorationAction.new(
				&"examine", "UI_ACTION_EXAMINE", Callable(self, "examine").bind(who)
			)
		)
	actions.append(
		ExplorationAction.new(&"recycle", "UI_ACTION_RECYCLE", Callable(self, "recycle").bind(who))
	)
	return actions


func is_recycled() -> bool:
	return _recycled


## Recycled litter has no actions left: the cell has become ordinary floor.
func is_spent() -> bool:
	return _recycled


func has_been_examined() -> bool:
	return _examined


## Examine: hands out one encyclopaedia info, once per visit.
func examine(_who: Node) -> void:
	if _examined or _recycled:
		return
	_examined = true
	if not INFO_SPECIES.is_empty():
		var sp: StringName = INFO_SPECIES[randi() % INFO_SPECIES.size()]
		GameSession.award_ifp(sp, GameEnums.IfpAction.EXAMINE_DECOR)


## Recycle: random objects plus a refreshed exploration ability, then ordinary floor.
func recycle(_who: Node) -> void:
	if _recycled:
		return
	_recycled = true
	# The cell becomes ORDINARY FLOOR, so the heap goes away entirely. Greying it out would read
	# as a dead obstacle, when in fact you walk over it.
	_remove_marker()
	var n := randi_range(loot_min, loot_max)
	for i in range(n):
		if not loot_pool.is_empty():
			GameSession.add_object(loot_pool[randi() % loot_pool.size()], 1)
	GameSession.refresh_random_exploration_ability()


## Persistence between visits: recycled litter stays ordinary floor, for good. Replacing
## examined decor is handled at the dungeon level.
func reset_between_visits() -> void:
	pass


func _spawn_visual() -> void:
	_add_marker(Color(0.35, 0.6, 0.35), 0.5, 0.75)  # a green heap, an obstacle
