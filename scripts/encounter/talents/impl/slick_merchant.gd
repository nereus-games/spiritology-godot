## Slick Merchant (fopin).
##
## On the FIRST 3 turns of the encounter:
##  - "Talking to a target changes its Weakness for this character's current one" — handled here
##    through [method on_talk_resolved]: a Talk from the bearer to a rival sets the rival's
##    weakness to the bearer's current one.
##  - "Rivals are 15 % more likely to Talk" — handled here through [method modify_talk_chance].
##    Note that in the current model a Talk's "effectiveness" is a proxy on talker_chance (see
##    EncounterManager._resolve_talk), so the +15% lands there. A deliberate approximation.
##
## The MENU half is NOT handled here and waits on the menu-mutation wiring: "on turn 1, and when
## this character has 10 % DEN or less, it can't Use Ability, but gets an extra action: Run Away,
## which costs 10 ETH" — with a QTE, and so fallible; the QTE is not built. It is expressed
## through [method modify_menu] so the manager or the agent can consult it when the time comes.
extends "res://scripts/encounter/talents/talent_script.gd"

const EARLY_TURNS := 3
const TALK_CHANCE_BONUS := 0.15
const RUN_AWAY_ETH := 10
const LOW_DEN_FRACTION := 0.1  ## "10 % DEN or less"


func modify_talk_chance(manager, _speaker, _target, base: float) -> float:
	if manager.round_number <= EARLY_TURNS:
		return clampf(base + TALK_CHANCE_BONUS, 0.0, 1.0)
	return base


func on_talk_resolved(manager, speaker, target, _effective: bool) -> void:
	if speaker != owner or target == null or manager.round_number > EARLY_TURNS:
		return
	if target.is_player == owner.is_player:  # rivals only
		return
	var pos = manager.timeline.position_of(owner)
	var my_weakness = owner.active_weakness(pos)
	target.override_weakness(my_weakness)
	manager.note_talent(
		_tr("LOG_TALENT_SLICK_MERCHANT") % [_label(), target.display_name(), owner.display_name()]
	)


func modify_menu(manager, kinds: Array) -> void:
	# The design doc's condition: turn 1, OR DEN at 10% or less. Then: no Use Ability, plus Run
	# Away.
	var low_den := owner.den <= roundi(owner.max_den * LOW_DEN_FRACTION)
	if manager.round_number == 1 or low_den:
		kinds.erase(EncounterAction.Kind.ABILITY)
		if not kinds.has(EncounterAction.Kind.FLEE):
			kinds.append(EncounterAction.Kind.FLEE)


func _label() -> String:
	return String(TranslationServer.translate(talent.name_key())) if talent else "Slick Merchant"
