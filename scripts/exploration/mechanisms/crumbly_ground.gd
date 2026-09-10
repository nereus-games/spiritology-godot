## Crumbly ground: the Dig action.
##
## From the design doc ("Mechanisms / Crumbly Grounds" and "Walls + Decors"). Standing ON the
## tile, the player can Dig by spending a spade. Digging hands out a random object, and/or an
## encyclopaedia info about a spirimonster from the associated pool, and/or springs a trap.
## Diggable once per visit, with an icon marking the tile afterwards. Crumbly ground cannot be
## Examined — Dig covers that.
##
## No `class_name`: `extends` by path. References the GameSession autoload, like
## player_controller: fine in game, since it is loaded after boot, but tests have to load it at
## runtime.
extends "res://scripts/exploration/mechanisms/dungeon_mechanism.gd"

const ExplorationAction := preload("res://scripts/exploration/exploration_action.gd")

const SPADE := &"spade"

## The spirimonsters a Dig can hand out an info about ("Walls + Decors").
const INFO_SPECIES: Array[StringName] = [
	&"mastel",
	&"kurkab",
	&"sopiark",
	&"firulis",
	&"skorpis",
	&"yilir",
]

## What a dig can hand out. Placeholder; the exact loot is design's to settle.
@export var loot_pool: Array[StringName] = [&"rune_stone", &"tea_drop", &"smoke_bomb"]
## How likely an encyclopaedia info comes on top of the object.
@export var info_chance := 0.5
## How likely a trap springs and poisons the digger. Placeholder.
@export var trap_chance := 0.25
@export var trap_poison_turns := 3
@export var trap_poison_per_turn := 5

var _dug := false


## The Dig action, offered only while the tile has not been dug and the player holds a spade.
func on_tile_actions(who: Node) -> Array:
	if _dug or not GameSession.has_object(SPADE):
		return []
	return [ExplorationAction.new(&"dig", "UI_ACTION_DIG", Callable(self, "dig").bind(who))]


## Whether the tile has already been dug this visit; the map shows an icon for it.
func has_been_dug() -> bool:
	return _dug


## Already dug this visit, so no Dig action left. This is also what the map reads to mark the
## tile, as the design doc asks: "an icon is shown on the dungeon map after it has been dug a
## first time".
func is_spent() -> bool:
	return _dug


## Digs: spends a spade, then hands out object, info and trap. With no spade, does nothing.
func dig(who: Node) -> void:
	if _dug or not GameSession.consume_object(SPADE):
		return
	_dug = true
	# Turned-over ground: greyed but NOT flattened. The plate is already almost flush with the
	# floor, and squashing it further would make it vanish.
	_grey_marker()
	# 1) A random object.
	if not loot_pool.is_empty():
		GameSession.add_object(loot_pool[randi() % loot_pool.size()], 1)
	# 2) An encyclopaedia info, optionally.
	if randf() < info_chance and not INFO_SPECIES.is_empty():
		var sp: StringName = INFO_SPECIES[randi() % INFO_SPECIES.size()]
		GameSession.award_ifp(sp, GameEnums.IfpAction.EXAMINE_DECOR)
	# 3) A trap, optionally, poisoning the digger.
	if randf() < trap_chance:
		var aff = who.get("affliction")
		if aff != null:
			aff.add_poison(trap_poison_turns, trap_poison_per_turn)


func reset_between_visits() -> void:
	_dug = false
	_respawn_marker()  # diggable again: the earth gets its colour back


func _spawn_visual() -> void:
	_add_marker(Color(0.5, 0.35, 0.2), 0.1, 0.9)  # earthy ground, very flat
