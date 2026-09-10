## Saving and loading, as JSON (autoload `SaveSystem`).
##
## Serialises [GameSession] — what a playthrough accumulates — and never [GameData], which
## is static and reloaded from the .tres files at boot.
extends Node

const SAVE_PATH := "user://spiritology_save.json"
const SAVE_VERSION := 1


## Writes the current session to disk. Returns OK or an error code.
func save_game() -> Error:
	var payload := {
		"version": SAVE_VERSION,
		"main_character": String(GameSession.main_character),
		"teammate": String(GameSession.teammate),
		"player_name": GameSession.player_name,
		"psy_score": GameSession.psy_score,
		"fde_count": GameSession.fde_count,
		"encyclopaedia_ifp": _stringify_keys(GameSession.encyclopaedia_ifp),
		# IFP earned per species by examining decor and ground, capped at 15.
		"exploration_examine_ifp": _stringify_keys(GameSession.exploration_examine_ifp),
		"dungeon_states": GameSession.dungeon_states,
		# Inventory: slugs as String, since JSON keys can only be strings.
		"inventory": _stringify_keys(GameSession.inventory),
		# The duo's persistent DEN/ETH, per party slot.
		"party_den":
		{
			"main": GameSession.get_den(GameSession.PartySlot.MAIN),
			"teammate": GameSession.get_den(GameSession.PartySlot.TEAMMATE),
		},
		"party_eth":
		{
			"main": GameSession.get_eth(GameSession.PartySlot.MAIN),
			"teammate": GameSession.get_eth(GameSession.PartySlot.TEAMMATE),
		},
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("[SaveSystem] cannot write: %s" % FileAccess.get_open_error())
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(payload, "\t"))
	return OK


## Reloads the session from disk. True if a save was actually loaded.
func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_error("[SaveSystem] cannot read: %s" % FileAccess.get_open_error())
		return false
	var data: Variant = JSON.parse_string(file.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		push_error("[SaveSystem] corrupt save file.")
		return false
	# TODO: migrate when data["version"] < SAVE_VERSION.
	GameSession.main_character = StringName(data.get("main_character", ""))
	GameSession.teammate = StringName(data.get("teammate", ""))
	GameSession.player_name = data.get("player_name", "")
	GameSession.psy_score = int(data.get("psy_score", 0))
	GameSession.fde_count = int(data.get("fde_count", 0))
	GameSession.encyclopaedia_ifp = _intify_values(data.get("encyclopaedia_ifp", {}))
	# Tolerant of a missing key, so that older saves still load.
	GameSession.exploration_examine_ifp = _intify_values(data.get("exploration_examine_ifp", {}))
	GameSession.dungeon_states = data.get("dungeon_states", {})
	# Keys back to StringName, quantities back to int.
	GameSession.inventory = _intify_values(data.get("inventory", {}))
	# Falls back to full DEN/ETH when the key is missing.
	var den: Dictionary = data.get("party_den", {})
	GameSession.set_den(GameSession.PartySlot.MAIN, int(den.get("main", GameSession.MAX_DEN)))
	GameSession.set_den(
		GameSession.PartySlot.TEAMMATE, int(den.get("teammate", GameSession.MAX_DEN))
	)
	var eth: Dictionary = data.get("party_eth", {})
	GameSession.set_eth(GameSession.PartySlot.MAIN, int(eth.get("main", GameSession.MAX_ETH)))
	GameSession.set_eth(
		GameSession.PartySlot.TEAMMATE, int(eth.get("teammate", GameSession.MAX_ETH))
	)
	return true


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


## JSON only accepts String keys.
func _stringify_keys(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[String(k)] = d[k]
	return out


## JSON reads numbers back as float; these counts are integers.
func _intify_values(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[StringName(k)] = int(d[k])
	return out
