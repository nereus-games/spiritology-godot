## Serene Waves (spodra).
##
## The ENCOUNTER half, handled here — "talking to your teammate will revitalise them and remove
## their weakness for the ongoing turn" — gives the teammate Y DEN back and strips its weakness
## for the current turn.
##
## The EXPLORATION halves are NOT handled here and wait on the dungeon mechanism framework:
## revealing the individuals' positions on the entry floor, and "meditating in a dungeon reveals
## traps at X tiles or less".
##
## Talk targets only RIVALS by default; this talent extends it to the TEAMMATE through
## [method allows_ally_talk] — the menu then adds the allies to Talk's targets, see
## EncounterManager.talk_targets — and [method on_talk_resolved] applies the healing.
extends "res://scripts/encounter/talents/talent_script.gd"

## PLACEHOLDER: the design doc writes "Y DEN" without a number. For scale, max_den = 100.
const TEAMMATE_DEN := 20


func allows_ally_talk(_manager) -> bool:
	return true


func on_talk_resolved(manager, speaker, target, _effective: bool) -> void:
	if speaker != owner or target == null:
		return
	# Only when talking to a TEAMMATE: same side, and not oneself.
	if target.is_player != owner.is_player or target == owner:
		return
	target.recover_den(TEAMMATE_DEN)
	target.override_weakness(GameEnums.Energy.NONE)  # stripped for the current turn
	manager.note_talent(
		(
			"%s revitalise %s (+%d DEN, faiblesse retirée)."
			% [_label(), target.display_name(), TEAMMATE_DEN]
		)
	)


func _label() -> String:
	return String(TranslationServer.translate(talent.name_key())) if talent else "Serene Waves"
