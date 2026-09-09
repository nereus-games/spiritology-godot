## Trick to Reveal (érzélak) — « Ending an encounter with an effective dialogue reveals on
## the map a chest or trap that hadn't been revealed yet. »
##
## Le DÉCLENCHEUR est en rencontre (finir sur un dialogue effectif), mais l'EFFET est une
## révélation sur la CARTE d'exploration. Les cibles existent désormais ([method Trap.reveal]
## et [method Chest.reveal], avec leur drapeau `revealed`), mais la carte ne dessine pas encore
## les mécanismes et la rencontre n'a pas de lien vers le donjon quitté : on surcharge donc
## [method on_encounter_end] pour marquer l'intention (STUB journalisé).
##
## Limite connue : « dialogue effectif de fin » suppose de suivre l'effectivité du DERNIER
## Talk de la rencontre. Le manager ne l'historise pas encore ; à brancher avec le système
## de dialogue (l'effectivité de Talk est elle-même un proxy, cf. EncounterManager._resolve_talk).
extends "res://scripts/encounter/talents/talent_script.gd"


func on_encounter_end(manager, result: StringName) -> void:
	if result == &"defeat":
		return
	# TODO: si le dernier dialogue a été effectif, révéler un coffre/piège non révélé sur la
	# carte — quand le framework de donjon existera.
	manager.note_talent(
		"%s : une révélation de carte pourrait suivre ce dialogue [à venir]." % _label()
	)


func _label() -> String:
	return String(TranslationServer.translate(talent.name_key())) if talent else "Trick to Reveal"
