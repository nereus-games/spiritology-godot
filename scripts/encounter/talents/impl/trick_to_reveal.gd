## Trick to Reveal (érzélak) — "Ending an encounter with an effective dialogue reveals on
## the map a chest or trap that hadn't been revealed yet."
##
## The TRIGGER is in the encounter — ending on an effective dialogue — but the EFFECT is a
## reveal on the exploration MAP. The targets now exist ([method Trap.reveal] and
## [method Chest.reveal], with their `revealed` flag), but the map does not draw mechanisms yet
## and the encounter has no link back to the dungeon it left. So [method on_encounter_end] is
## overridden to record the intent: a logged STUB.
##
## A known limit: "an effective dialogue at the end" means tracking whether the LAST Talk of the
## encounter was effective. The manager does not keep that history yet; to be wired with the
## dialogue system (Talk's effectiveness is itself a proxy, see
## EncounterManager._resolve_talk).
extends "res://scripts/encounter/talents/talent_script.gd"


func on_encounter_end(manager, result: StringName) -> void:
	if result == &"defeat":
		return
	# TODO: if the last dialogue was effective, reveal an unrevealed chest or trap on the map —
	# once the dungeon framework exists.
	manager.note_talent(
		"%s : une révélation de carte pourrait suivre ce dialogue [à venir]." % _label()
	)


func _label() -> String:
	return String(TranslationServer.translate(talent.name_key())) if talent else "Trick to Reveal"
