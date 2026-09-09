## Serene Waves (spodra).
##
## Volet RENCONTRE (traité ici) — « talking to your teammate will revitalise them and
## remove their weakness for the ongoing turn » : parler à l'équipier lui rend Y DEN et
## retire sa faiblesse pour le tour courant.
##
## Volets EXPLORATION (NON traités ici — attendent le framework de mécanismes de donjon) :
## révéler la position des individus au niveau d'entrée, et « meditating in a dungeon
## reveals traps at X tiles or less ».
##
## Talk ne cible par défaut que les RIVAUX ; ce talent l'étend à l'ÉQUIPIER via
## [method allows_ally_talk] (le menu ajoute alors les alliés aux cibles de Talk, cf.
## EncounterManager.talk_targets), et [method on_talk_resolved] applique le soin.
extends "res://scripts/encounter/talents/talent_script.gd"

## PLACEHOLDER — Notion écrit « Y DEN » sans le chiffrer (repère : max_den = 100).
const TEAMMATE_DEN := 20


func allows_ally_talk(_manager) -> bool:
	return true


func on_talk_resolved(manager, speaker, target, _effective: bool) -> void:
	if speaker != owner or target == null:
		return
	# Seulement en parlant à un ÉQUIPIER (même camp, pas soi-même).
	if target.is_player != owner.is_player or target == owner:
		return
	target.recover_den(TEAMMATE_DEN)
	target.override_weakness(GameEnums.Energy.NONE)  # retirée pour le tour courant
	manager.note_talent(
		(
			"%s revitalise %s (+%d DEN, faiblesse retirée)."
			% [_label(), target.display_name(), TEAMMATE_DEN]
		)
	)


func _label() -> String:
	return String(TranslationServer.translate(talent.name_key())) if talent else "Serene Waves"
