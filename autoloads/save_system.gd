## Sauvegarde / chargement de la partie en JSON (autoload `SaveSystem`).
##
## Format JSON, comme le proto. Sérialise l'état de [GameSession] (données dynamiques),
## jamais [GameData] (statique, rechargé au boot depuis les .tres).
extends Node

const SAVE_PATH := "user://spiritology_save.json"
const SAVE_VERSION := 1


## Écrit l'état courant de la session sur le disque. Renvoie OK ou un code d'erreur.
func save_game() -> Error:
	var payload := {
		"version": SAVE_VERSION,
		"main_character": String(GameSession.main_character),
		"teammate": String(GameSession.teammate),
		"player_name": GameSession.player_name,
		"psy_score": GameSession.psy_score,
		"fde_count": GameSession.fde_count,
		"encyclopaedia_ifp": _stringify_keys(GameSession.encyclopaedia_ifp),
		# IFP cumulés par espèce via Examine decor/ground (plafond exploration de 15).
		"exploration_examine_ifp": _stringify_keys(GameSession.exploration_examine_ifp),
		"dungeon_states": GameSession.dungeon_states,
		# Inventaire : slugs sérialisés en String (clés JSON), quantités int.
		"inventory": _stringify_keys(GameSession.inventory),
		# DEN/ETH persistants du duo, par emplacement (clés String pour JSON).
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
		push_error("[SaveSystem] écriture impossible : %s" % FileAccess.get_open_error())
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(payload, "\t"))
	return OK


## Recharge la session depuis le disque. Renvoie true si une sauvegarde a été chargée.
func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_error("[SaveSystem] lecture impossible : %s" % FileAccess.get_open_error())
		return false
	var data: Variant = JSON.parse_string(file.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		push_error("[SaveSystem] sauvegarde corrompue.")
		return false
	# TODO: migration si data["version"] < SAVE_VERSION.
	GameSession.main_character = StringName(data.get("main_character", ""))
	GameSession.teammate = StringName(data.get("teammate", ""))
	GameSession.player_name = data.get("player_name", "")
	GameSession.psy_score = int(data.get("psy_score", 0))
	GameSession.fde_count = int(data.get("fde_count", 0))
	GameSession.encyclopaedia_ifp = _intify_values(data.get("encyclopaedia_ifp", {}))
	# IFP Examine-decor cumulés par espèce ; tolérant si clé absente (anciennes saves).
	GameSession.exploration_examine_ifp = _intify_values(data.get("exploration_examine_ifp", {}))
	GameSession.dungeon_states = data.get("dungeon_states", {})
	# Inventaire : clés relues en StringName, quantités en int ; tolérant si clé absente.
	GameSession.inventory = _intify_values(data.get("inventory", {}))
	# DEN/ETH du duo : relecture tolérante, repli sur le maximum si clé absente.
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


## JSON n'accepte que des clés String ; on convertit les StringName en String.
func _stringify_keys(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[String(k)] = d[k]
	return out


## Reconvertit les valeurs IFP (JSON les relit en float) en int.
func _intify_values(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[StringName(k)] = int(d[k])
	return out
