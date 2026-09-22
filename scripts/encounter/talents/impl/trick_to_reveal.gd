## Trick to Reveal (érzélak) — "Ending an encounter with an effective dialogue reveals on
## the map a chest or trap that hadn't been revealed yet."
##
## The TRIGGER is in the encounter — ending on an effective dialogue — but the EFFECT is a
## reveal on the exploration MAP. The targets now exist ([method Trap.reveal] and
## [method Chest.reveal], with their `revealed` flag), and the minimap DOES draw mechanisms
## ([method DungeonMechanism.shows_on_map]): revealing a TRAP would therefore show, since
## [method Trap.shows_on_map] gates on `revealed`. Revealing a CHEST would not — [Chest] does
## not override `shows_on_map`, so the map already draws every chest, known or not (the TODO in
## `chest.gd`). What is missing either way is a link back from the encounter to the dungeon it
## was entered from. So [method on_encounter_end] is overridden to record the intent: a logged
## STUB.
##
## A known limit: "an effective dialogue at the end" means tracking whether the LAST Talk of the
## encounter was effective. The manager does not keep that history yet; to be wired with the
## dialogue system (Talk's effectiveness is itself a proxy, see
## EncounterManager._resolve_talk).
extends "res://scripts/encounter/talents/talent_script.gd"


func on_encounter_end(manager, result: StringName) -> void:
	if result == &"defeat":
		return
	# TODO: if the last dialogue was effective, reveal an unrevealed chest or trap on the map.
	# The dungeon side is ready ([method Trap.reveal], [method Chest.reveal]); what is missing is
	# a way for an encounter talent to reach the dungeon it was entered from.
	manager.note_talent(_tr("LOG_TALENT_TRICK_TO_REVEAL") % _label())


func _label() -> String:
	return String(TranslationServer.translate(talent.name_key())) if talent else "Trick to Reveal"
