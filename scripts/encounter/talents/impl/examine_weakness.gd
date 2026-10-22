## Examine Weakness (gélmi) — "If character uses an ability that touches its target's
## current weakness, they get a little info on target. If character is targeted by an
## Ability that touches their current weakness, they get a little info on the Ability's user."
##
## The manager calls [method on_weakness_touched] whenever an ability touches an active weakness
## the bearer is involved in, as attacker OR as target. "A little info" is one info fragment
## (3 IFP, [constant GameEnums.IfpAction.WEAKNESS_INFO]) on the other individual, announced
## through [method EncounterManager.gather_weakness_info] and so [signal
## EncounterManager.ifp_earned], like an Examine's. It goes to a rival's species only, and only
## when the bearer is a player character; the weakness is not exposed, nor the amount scaled
## by the Examine bonuses.
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
	if not manager.gather_weakness_info(owner, other):
		return
	manager.note_talent(_tr("LOG_TALENT_EXAMINE_WEAKNESS") % [_label(), other.display_name()])


func _label() -> String:
	return String(TranslationServer.translate(talent.name_key())) if talent else "Examine Weakness"
