## Examine Weakness (gélmi) — "If character uses an ability that touches its target's
## current weakness, they get a little info on target. If character is targeted by an
## Ability that touches their current weakness, they get a little info on the Ability's user."
##
## The manager calls [method on_weakness_touched] whenever an ability touches an active weakness
## the bearer is involved in, as attacker OR as target. The EFFECT — getting "a little info" on
## the other — belongs to the encyclopaedia-during-combat, which does not exist yet: a logged
## STUB, to be filled in once Examine's info gain does (same status as
## EncounterContext.grant_examine_bonus).
extends "res://scripts/encounter/talents/talent_script.gd"


func on_weakness_touched(manager, attacker, defender, _ability) -> void:
	var other = null
	if attacker == owner:
		other = defender  # info on the target
	elif defender == owner:
		other = attacker  # info on whoever used the ability
	else:
		return
	if other == null:
		return
	# TODO: grant an encyclopaedia info fragment about `other` once that system exists.
	manager.note_talent(_tr("LOG_TALENT_EXAMINE_WEAKNESS") % [_label(), other.display_name()])


func _label() -> String:
	return String(TranslationServer.translate(talent.name_key())) if talent else "Examine Weakness"
