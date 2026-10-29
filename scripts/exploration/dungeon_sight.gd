## What the player can see of a dungeon: the model behind "In the Dark".
##
## In a dark dungeon, sight is limited to one tile; rivals beyond it are HEARD but not seen;
## Meditate shows every rival for 2 moves; and an NPC quest can light an area for good. A
## dungeon is dark when its [member DungeonConfig.dark] flag says so, and also whenever the PSY
## score is above the fourth rung ([method GameSession.psy_above]).
##
## Held by the [DungeonManager] as [member DungeonManager.sight]. It holds the rules only; it
## draws nothing. The one visible effect so far is on the rivals: [method DungeonManager.refresh_sight]
## hides the ones [method rival_visible] says the player cannot see, and a message carries the
## cue for the ones heard ([method heard_message]). Drawing the dark itself comes later and
## should ask [method tile_visible].
##
## Decisions where the doc is silent (also in docs/roadmap.md, "Decisions taken in code"):
## - "one tile" is the tile the player stands on and its four neighbours on the same floor
##   ([member BalanceData.dark_sight_range] = 1, Manhattan);
## - a rival is heard within [member BalanceData.dark_hearing_range] tiles (Manhattan, a floor
##   of difference counting double) and not seen; the cue is a message naming a compass
##   direction of the dungeon, not of the player, and is posted only when a rival becomes
##   audible, not on each turn it stays so;
## - Meditate's reveal lasts [member BalanceData.dark_reveal_moves] player moves, counted down by
##   [method DungeonManager.advance_turn]; meditating again restarts the count;
## - a lit area is lit for the rest of the visit: tiles in it are fully seen, and rivals standing
##   on them too. It is not saved between visits (no dungeon state exists yet).
##
## No `class_name` (the CLI class-cache trap): preloaded.
extends RefCounted

## Emitted when the set of lit tiles changes.
signal lit_changed

## Tiles lit by a light source or a quest: tile:Vector3i -> true.
var _lit: Dictionary = {}

## Player moves left during which Meditate's reveal holds.
var reveal_moves_left := 0

## The rivals that were audible at the last [method heard_message], so a cue is not repeated.
var _was_heard: Dictionary = {}

var _dungeon


func _init(dungeon) -> void:
	_dungeon = dungeon


## Is the dungeon dark? Flagged so by its config, or the PSY is above rung 4.
func is_dark() -> bool:
	var config = _dungeon.config
	if config != null and config.dark:
		return true
	return GameSession.psy_above(4)


# --------------------------------------------------------------------------
# Light
# --------------------------------------------------------------------------


## Lights every tile of `tiles` for the rest of the visit. The hook an NPC quest calls.
func light_tiles(tiles: Array) -> void:
	var changed := false
	for t in tiles:
		if not _lit.has(t):
			_lit[t] = true
			changed = true
	if changed:
		lit_changed.emit()


## Lights the floor tiles within `radius` (Manhattan, same floor) of `center`: a light source.
func light_radius(center: Vector3i, radius: int) -> void:
	var tiles: Array = []
	for dx in range(-radius, radius + 1):
		for dz in range(-radius, radius + 1):
			if absi(dx) + absi(dz) <= radius:
				var t := center + Vector3i(dx, 0, dz)
				if _dungeon.is_floor(t):
					tiles.append(t)
	light_tiles(tiles)


## Lights every floor tile of the box between `a` and `b` (inclusive, `a`'s floor): a lit room.
func light_box(a: Vector3i, b: Vector3i) -> void:
	var tiles: Array = []
	for x in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
		for z in range(mini(a.z, b.z), maxi(a.z, b.z) + 1):
			var t := Vector3i(x, a.y, z)
			if _dungeon.is_floor(t):
				tiles.append(t)
	light_tiles(tiles)


func is_lit(tile: Vector3i) -> bool:
	return _lit.has(tile)


## Puts every light out (a new visit).
func clear_light() -> void:
	if not _lit.is_empty():
		_lit.clear()
		lit_changed.emit()


# --------------------------------------------------------------------------
# Sight
# --------------------------------------------------------------------------


## Can the player see `tile`? Everything in a lit dungeon; in a dark one, the tiles within
## [member BalanceData.dark_sight_range] of the player on their floor, and the lit ones.
func tile_visible(tile: Vector3i) -> bool:
	if not is_dark() or _lit.has(tile):
		return true
	var here: Vector3i = _dungeon.player_tile()
	return tile.y == here.y and _manhattan(tile, here) <= BalanceData.current().dark_sight_range


## Does the player see this rival? Always in a lit dungeon; in a dark one only when it is on a
## visible tile or Meditate is revealing the rivals.
func rival_visible(rival: Node) -> bool:
	if not is_dark() or reveal_moves_left > 0:
		return true
	return tile_visible(rival.tile)


## Does the player hear this rival? It is not seen but lies within hearing range.
func rival_heard(rival: Node) -> bool:
	if rival_visible(rival):
		return false
	var here: Vector3i = _dungeon.player_tile()
	var d := _manhattan(rival.tile, here) + 2 * absi(rival.tile.y - here.y)
	return d <= BalanceData.current().dark_hearing_range


## Meditate: every rival is shown for [member BalanceData.dark_reveal_moves] moves.
func reveal_rivals() -> void:
	reveal_moves_left = BalanceData.current().dark_reveal_moves


## One player move has passed.
func on_move() -> void:
	if reveal_moves_left > 0:
		reveal_moves_left -= 1


## The message for the rivals that BECAME audible since the last call, or "" when there are none.
## Names the compass direction of the nearest of them (north is -z, east +x).
func heard_message() -> String:
	var here: Vector3i = _dungeon.player_tile()
	var nearest: Node = null
	var nearest_d := 1 << 30
	var now: Dictionary = {}
	var fresh := false
	for rival in _dungeon.rivals():
		if not is_instance_valid(rival) or not rival_heard(rival):
			continue
		now[rival] = true
		if not _was_heard.has(rival):
			fresh = true
		var d := _manhattan(rival.tile, here)
		if d < nearest_d:
			nearest_d = d
			nearest = rival
	_was_heard = now
	if not fresh or nearest == null:
		return ""
	var line := String(TranslationServer.translate("UI_DARK_HEARD"))
	return line % direction_name(nearest.tile - here)


## The translated compass word for an offset: its dominant horizontal axis.
static func direction_name(offset: Vector3i) -> String:
	var key := "UI_DARK_DIR_NORTH"
	if absi(offset.x) > absi(offset.z):
		key = "UI_DARK_DIR_EAST" if offset.x > 0 else "UI_DARK_DIR_WEST"
	elif offset.z > 0:
		key = "UI_DARK_DIR_SOUTH"
	return String(TranslationServer.translate(key))


static func _manhattan(a: Vector3i, b: Vector3i) -> int:
	return absi(a.x - b.x) + absi(a.z - b.z)
