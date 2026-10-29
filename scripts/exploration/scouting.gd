## The watch of Static Camouflage, from the design doc: the player turns into a motionless object
## and the wandering rival groups are shown ONE AT A TIME — their exact number and species. At
## each, the player either takes that group on or keeps waiting for the next. There are 2 to 4
## groups in all; waiting through the last one ends the watch with "It seems no other group is
## wandering here". Taking a group on ends the transformation, and no further group is shown.
##
## Held by the [DungeonManager] as [member DungeonManager.scouting]. The choice is two
## [ExplorationAction]s that replace the usual menu while the watch lasts ([method actions]); the
## HUD shows [method description] for as long as a group is pending.
##
## Decisions where the doc is silent:
## - which groups are shown: a random draw among the groups on the map, none twice. Fewer than
##   the draw when the map holds fewer, none at all when it holds none;
## - the watch costs no turn: nothing on the map moves while the player picks;
## - the player cannot move for the watch (the transformation is immobile).
##
## - a group holding a Forlorn member is [member BalanceData.camouflage_forlorn_weight] times as
##   likely to be among those shown (the doc has Forlorn shapes "likelier than by default"), and
##   a Forlorn member is shown as such;
##
## ## TODO: "X % chances (Y % next to litter) of including unknown species" — groups that are not
## on the map — is not built: it needs the litter and a group that is shown without existing.
##
## No `class_name` (the CLI class-cache trap): preloaded.
extends RefCounted

const ExplorationAction := preload("res://scripts/exploration/exploration_action.gd")

const MIN_GROUPS := 2
const MAX_GROUPS := 4

var active := false

var _dungeon
var _player
var _queue: Array = []
var _shown := 0
var _total := 0


func _init(dungeon) -> void:
	_dungeon = dungeon


## Starts the watch over `groups` (the rival groups on the map). Draws 2 to 4 of them with `rng`.
## With none to show, says so and does not start. `player` is held still until the watch ends.
func begin(groups: Array, rng: RandomNumberGenerator, player = null) -> void:
	end()
	var pool: Array = []
	for g in groups:
		if is_instance_valid(g):
			pool.append(g)
	var wanted := rng.randi_range(MIN_GROUPS, MAX_GROUPS)
	_queue = []
	while _queue.size() < wanted and not pool.is_empty():
		_queue.append(pool.pop_at(_draw_index(pool, rng)))
	_total = _queue.size()
	_shown = 0
	if _queue.is_empty():
		_dungeon.post_message(TranslationServer.translate("UI_SCOUT_NONE_LEFT"))
		return
	active = true
	_player = player
	if _player != null:
		_player.input_locked = true
	_shown = 1


## The index of the next group shown: weighted, a group with a Forlorn member counting for
## [member BalanceData.camouflage_forlorn_weight].
func _draw_index(pool: Array, rng: RandomNumberGenerator) -> int:
	var forlorn_weight := maxi(1, BalanceData.current().camouflage_forlorn_weight)
	var weights: Array[int] = []
	var total := 0
	for g in pool:
		var w := forlorn_weight if has_forlorn(g) else 1
		weights.append(w)
		total += w
	var roll := rng.randi_range(1, total)
	for i in weights.size():
		roll -= weights[i]
		if roll <= 0:
			return i
	return pool.size() - 1


## Whether a group holds a Forlorn member.
static func has_forlorn(group: Node) -> bool:
	for m in group.members:
		if m.forlorn:
			return true
	return false


## The group currently shown, or null.
func current() -> Node:
	if not active or _shown < 1 or _shown > _queue.size():
		return null
	return _queue[_shown - 1]


## What the player sees of the current group: its place in the watch, and its exact makeup.
func description() -> String:
	var group := current()
	if group == null:
		return ""
	# Keyed by species, then by shape, so that a Forlorn member is told apart from its kin.
	var counts: Dictionary = {}
	for m in group.members:
		var key := [m.species_id, m.forlorn]
		counts[key] = int(counts.get(key, 0)) + 1
	var parts: Array[String] = []
	for key in counts:
		var id: StringName = key[0]
		var name := String(id)
		var sp = GameData.species(id)
		if sp != null:
			name = String(TranslationServer.translate(sp.name_key()))
		var line := String(
			TranslationServer.translate("UI_SCOUT_MEMBER_FORLORN" if key[1] else "UI_SCOUT_MEMBER")
		)
		parts.append(line % [counts[key], name])
	var head := String(TranslationServer.translate("UI_SCOUT_GROUP"))
	return head % [_shown, _total, ", ".join(parts)]


## The choice offered while a group is shown. Empty outside a watch.
func actions() -> Array:
	if not active:
		return []
	return [
		ExplorationAction.new(&"scout_engage", "UI_ACTION_SCOUT_ENGAGE", Callable(self, "engage")),
		ExplorationAction.new(&"scout_wait", "UI_ACTION_SCOUT_WAIT", Callable(self, "wait")),
	]


## Takes the shown group on: the transformation is over, no other group is shown, and an
## encounter is requested.
func engage() -> void:
	var group := current()
	if group == null:
		return
	end()
	_dungeon.request_encounter(group, false)


## Keeps waiting: the next group is shown, or the watch ends when that was the last.
func wait() -> void:
	if not active:
		return
	_shown += 1
	if _shown > _queue.size():
		end()
		_dungeon.post_message(TranslationServer.translate("UI_SCOUT_NONE_LEFT"))


## Ends the watch and lets the player move again.
func end() -> void:
	active = false
	_queue = []
	_shown = 0
	_total = 0
	if _player != null and is_instance_valid(_player):
		_player.input_locked = false
	_player = null
