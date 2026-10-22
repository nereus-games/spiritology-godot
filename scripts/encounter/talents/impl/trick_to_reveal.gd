## Trick to Reveal (érzélak) — "Ending an encounter with an effective dialogue reveals on
## the map a chest or trap that hadn't been revealed yet."
##
## The TRIGGER is in the encounter — ending on an effective dialogue — but the EFFECT is a
## reveal on the exploration MAP. The encounter reaches the map through one narrow handle,
## [member EncounterManager.map_reveal], that whoever opened the encounter hands over; here it
## is [method DungeonManager.reveal_nearest_hidden] (the closest hidden chest or trap, see
## there). The manager never sees the dungeon.
##
## "An effective dialogue at the end" is read as: the LAST Talk resolved in the encounter was
## effective ([member EncounterManager.last_talk_effective]). Talk's effectiveness is itself a
## proxy, see EncounterManager._resolve_talk. A defeat reveals nothing, and neither does an
## encounter with no Talk at all.
extends "res://scripts/encounter/talents/talent_script.gd"


func on_encounter_end(manager, result: StringName) -> void:
	if result == &"defeat" or not manager.last_talk_effective:
		return
	if manager.reveal_on_map():
		manager.note_talent(_tr("LOG_TALENT_TRICK_TO_REVEAL") % _label())


func _label() -> String:
	return String(TranslationServer.translate(talent.name_key())) if talent else "Trick to Reveal"
