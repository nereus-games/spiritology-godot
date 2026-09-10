## A chest.
##
## From the design doc ("Mechanisms / Chest"). A rare mechanism: walking onto it hands the
## player objects. Some chests are really disguised teleport traps ([member is_trap]), with
## nothing to tell them apart by eye. Opened once only, across visits included.
##
## Two other pages of the design doc mention chests, and both are wired up here:
##  - the "Reveal Traps" talent (razél): "When a chest attempts to teleport players, they can
##    decide to teleport or not. The chest gives 1 or more object no matter what, but more if
##    players choose to teleport." So a trapped chest offers a CHOICE, through the tile's action
##    menu like the dieverting, and hands out loot either way;
##  - the "Trick to Reveal" talent (érzélak): reveals on the map "a chest or trap that hadn't
##    been revealed yet", hence [member revealed] and [method reveal], mirroring [Trap].
##
## No `class_name`: `extends` by path. References the GameSession autoload.
extends "res://scripts/exploration/mechanisms/dungeon_mechanism.gd"

const ExplorationAction := preload("res://scripts/exploration/exploration_action.gd")

## The talent that makes a trapped chest's teleport optional ("Reveal Traps").
const REVEAL_TRAPS := &"reveal_traps"

## A trapped chest: instead of handing out objects, it teleports whoever opens it.
@export var is_trap := false

## What a chest can hold. Placeholder.
@export var loot_pool: Array[StringName] = [&"rune_stone", &"tea_drop", &"smoke_bomb", &"spade"]
@export var loot_min := 1
@export var loot_max := 3

## Loot from a TRAPPED chest opened by a duo carrying "Reveal Traps". The design doc requires
## "1 or more object no matter what, but more if players choose to teleport". Placeholder
## magnitudes, respecting the doc's only constraint: accepted > declined >= 1.
@export var trap_loot_declined := 1
@export var trap_loot_accepted := 3

## FIXED contents: when not empty, the chest hands out EXACTLY these objects, duplicates
## included, instead of drawing from [member loot_pool]. Used by the dieverting, which drops the
## objects it makes you lose into a chest placed where it stood.
@export var fixed_loot: Array[StringName] = []

## The chest is known to the player, by having been stepped on or revealed by "Trick to
## Reveal". Does NOT imply knowing whether it is trapped — the design doc makes these DISGUISED
## traps.
## ## TODO: the map does not draw mechanisms yet; this flag is what it will read (same job as
## `Trap.revealed`).
@export var revealed := false

var _opened := false
## A trapped chest met by a duo carrying "Reveal Traps": the choice — accept or decline the
## teleport — is pending on the tile, like the dieverting's destroy-or-submit.
var _pending := false


func is_opened() -> bool:
	return _opened


## An opened chest has nothing left to give.
func is_spent() -> bool:
	return _opened


func is_pending() -> bool:
	return _pending


## Reveals the chest on the map without opening it (the "Trick to Reveal" talent).
func reveal() -> void:
	revealed = true


func on_enter(who: Node) -> void:
	if _opened:
		return
	var is_player := _dungeon == null or _dungeon.is_player(who)
	if is_player:
		revealed = true  # we stepped on it, so the chest is no longer an unknown
	if is_trap:
		# A disguised trap, and like any trap it applies to rivals too (the design doc's Traps
		# page, "rivals too"). The choice, though, is only ever offered to the player.
		if is_player and GameSession.party_has_talent(REVEAL_TRAPS):
			_pending = true
			return
		_spring(who)
		return
	# A loot chest: only the player picks anything up, since rivals have no inventory. A rival
	# walking over it therefore does NOT consume it — the loot waits for the player.
	if not is_player:
		return
	_close()
	_deliver(_roll_loot())


## What is offered while the "Reveal Traps" choice is pending: teleport or not, with loot either
## way, and more of it if you accept.
func on_tile_actions(who: Node) -> Array:
	if _opened or not _pending:
		return []
	return [
		ExplorationAction.new(
			&"chest_teleport",
			"UI_ACTION_CHEST_TELEPORT",
			Callable(self, "accept_teleport").bind(who)
		),
		ExplorationAction.new(
			&"chest_decline",
			"UI_ACTION_CHEST_DECLINE",
			Callable(self, "decline_teleport").bind(who)
		),
	]


## The "Reveal Traps" choice: accept the teleport, for more generous loot.
func accept_teleport(who: Node) -> void:
	if _opened or not _pending:
		return
	_close()
	_deliver(_pick_from_pool(trap_loot_accepted))
	_teleport(who)


## The "Reveal Traps" choice: decline the teleport; the chest hands out loot anyway. The trap
## never springs, so it does not break invisibility (the fog mantel rule).
func decline_teleport(_who: Node) -> void:
	if _opened or not _pending:
		return
	_close()
	_deliver(_pick_from_pool(trap_loot_declined))


## The trap springs: a bare teleport, no loot. The ordinary case, without the talent.
func _spring(who: Node) -> void:
	_close()
	_teleport(who)


func _teleport(who: Node) -> void:
	if _dungeon != null:
		_dungeon.teleport_actor(who)
	# A trap that springs breaks invisibility (the fog mantel rule), chest or not.
	if is_instance_valid(who) and who.has_method("clear_invisibility"):
		who.clear_invisibility()


## Marks the chest as opened: no more actions, and an inert visual like a spent trap, so nobody
## comes back to it hoping for loot.
func _close() -> void:
	_opened = true
	_pending = false
	_mark_spent()


## The chest's contents: the fixed ones when set, by the dieverting, otherwise a draw.
func _roll_loot() -> Array[StringName]:
	if not fixed_loot.is_empty():
		return fixed_loot.duplicate()
	return _pick_from_pool(randi_range(loot_min, loot_max))


## `count` objects drawn at random from [member loot_pool]; duplicates are possible.
func _pick_from_pool(count: int) -> Array[StringName]:
	var picked: Array[StringName] = []
	if loot_pool.is_empty():
		return picked
	for i in range(count):
		picked.append(loot_pool[randi() % loot_pool.size()])
	return picked


## Adds the loot to the inventory and announces it in the HUD's message banner.
func _deliver(loot: Array[StringName]) -> void:
	if loot.is_empty():
		return
	var names: Array[String] = []
	for object_id in loot:
		GameSession.add_object(object_id, 1)
		var data: ObjectData = GameData.object(object_id)
		names.append(tr(data.name_key()) if data != null else String(object_id))
	if _dungeon != null:
		_dungeon.post_message(tr("UI_CHEST_LOOT") % ", ".join(names))


## Opened chests stay opened between visits — no rearming. A choice left hanging, on the other
## hand, does not survive leaving the dungeon: the chest is intact again.
func reset_between_visits() -> void:
	_pending = false


func _spawn_visual() -> void:
	_add_marker(Color(0.75, 0.6, 0.25), 0.35, 0.55)  # gold chest, identical whether trapped or not
