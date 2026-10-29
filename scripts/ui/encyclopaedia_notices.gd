## Turns the encyclopaedia's signals into short lines for the exploration HUD's banner.
##
## Deliberately small: a first-in-first-out list of translated lines, filled by listening to
## [GameSession] and emptied by the HUD, one line at a time. Several things can happen in a single
## frame (a page assembled, the ability it unlocks), and the banner shows one message.
##
## What is announced, and what is not (also recorded in the roadmap):
## - fragments formed, with the page's new percentage: the moment IFP become something to hold;
## - an ability unlocked, by name and species;
## - a main page assembled, which is also when its Forlorn page opens, and a Forlorn page
##   assembled.
## Not announced: `encyclopaedia_progress` and `encyclopaedia_page_changed`, which fire on every
## IFP and would turn the banner into a ticker; the screens that draw a page listen to them.
##
## Every line goes through a translation key (`NOTICE_ENC_*`), none is written out here. No
## `class_name` (the CLI class-cache trap): preloaded. References the GameSession autoload.
extends RefCounted

## The lines waiting to be shown, oldest first.
var pending: Array[String] = []


## Starts listening to the session. Call once.
func connect_session() -> void:
	GameSession.encyclopaedia_fragments_formed.connect(_on_fragments_formed)
	GameSession.encyclopaedia_ability_unlocked.connect(_on_ability_unlocked)
	GameSession.encyclopaedia_page_assembled.connect(_on_page_assembled)


## Stops listening, for a HUD that leaves the tree.
func disconnect_session() -> void:
	if GameSession.encyclopaedia_fragments_formed.is_connected(_on_fragments_formed):
		GameSession.encyclopaedia_fragments_formed.disconnect(_on_fragments_formed)
	if GameSession.encyclopaedia_ability_unlocked.is_connected(_on_ability_unlocked):
		GameSession.encyclopaedia_ability_unlocked.disconnect(_on_ability_unlocked)
	if GameSession.encyclopaedia_page_assembled.is_connected(_on_page_assembled):
		GameSession.encyclopaedia_page_assembled.disconnect(_on_page_assembled)


func has_pending() -> bool:
	return not pending.is_empty()


## Removes and returns the oldest line, or "" when there is none.
func take() -> String:
	return pending.pop_front() if not pending.is_empty() else ""


func _on_fragments_formed(species_id: StringName, forlorn: bool, count: int) -> void:
	var key := "NOTICE_ENC_FRAGMENTS_FORLORN" if forlorn else "NOTICE_ENC_FRAGMENTS"
	_push(key, [_species(species_id), count, GameSession.page_ifp(species_id, forlorn)])


func _on_ability_unlocked(species_id: StringName, ability_id: StringName) -> void:
	_push("NOTICE_ENC_ABILITY", [_ability(ability_id), _species(species_id)])


func _on_page_assembled(species_id: StringName, forlorn: bool) -> void:
	if forlorn:
		_push("NOTICE_ENC_FORLORN_COMPLETE", [_species(species_id)])
	else:
		_push("NOTICE_ENC_PAGE_COMPLETE", [_species(species_id)])


func _push(key: String, args: Array) -> void:
	pending.append(String(TranslationServer.translate(key)) % args)


func _species(species_id: StringName) -> String:
	var sp: SpeciesData = GameData.species(species_id)
	return String(TranslationServer.translate(sp.name_key())) if sp != null else String(species_id)


func _ability(ability_id: StringName) -> String:
	var ab: AbilityData = GameData.ability(ability_id)
	return (
		String(TranslationServer.translate(ab.name_key())) if ab != null else String(ability_id)
	)
