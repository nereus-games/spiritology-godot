## Slick Merchant (fopin).
##
## Sur les 3 PREMIERS tours de la rencontre :
##  - « Talking to a target changes its Weakness for this character's current one » —
##    traité ici via [method on_talk_resolved] : un Talk du porteur vers un rival cale la
##    faiblesse du rival sur celle, courante, du porteur.
##  - « Rivals are 15 % more likely to Talk » — traité ici via [method modify_talk_chance].
##    NB : dans le modèle actuel, l'« effectivité » d'un Talk est un proxy sur talker_chance
##    (cf. EncounterManager._resolve_talk), donc ce +15 % s'y applique — approximation assumée.
##
## Volet MENU (NON traité ici — attend le câblage « mutation de menu ») : « on turn 1, and
## when this character has 10 % DEN or less, it can't Use Ability, but gets an extra action:
## Run Away, which costs 10 ETH » (avec QTE, donc faillible — QTE non bâti). Exprimé par
## [method modify_menu] pour que le manager/agent puisse le consulter le moment venu.
extends "res://scripts/encounter/talents/talent_script.gd"

const EARLY_TURNS := 3
const TALK_CHANCE_BONUS := 0.15
const RUN_AWAY_ETH := 10
const LOW_DEN_FRACTION := 0.1  ## « 10 % DEN or less »


func modify_talk_chance(manager, _speaker, _target, base: float) -> float:
	if manager.round_number <= EARLY_TURNS:
		return clampf(base + TALK_CHANCE_BONUS, 0.0, 1.0)
	return base


func on_talk_resolved(manager, speaker, target, _effective: bool) -> void:
	if speaker != owner or target == null or manager.round_number > EARLY_TURNS:
		return
	if target.is_player == owner.is_player:  # cible un rival uniquement
		return
	var pos = manager.timeline.position_of(owner)
	var my_weakness = owner.active_weakness(pos)
	target.override_weakness(my_weakness)
	manager.note_talent(
		(
			"%s : la faiblesse de %s prend celle de %s."
			% [_label(), target.display_name(), owner.display_name()]
		)
	)


func modify_menu(manager, kinds: Array) -> void:
	# Condition Notion : 1er tour, OU DEN ≤ 10 %. Alors : pas de Use Ability, + Run Away.
	var low_den := owner.den <= roundi(owner.max_den * LOW_DEN_FRACTION)
	if manager.round_number == 1 or low_den:
		kinds.erase(EncounterAction.Kind.ABILITY)
		if not kinds.has(EncounterAction.Kind.FLEE):
			kinds.append(EncounterAction.Kind.FLEE)


func _label() -> String:
	return String(TranslationServer.translate(talent.name_key())) if talent else "Slick Merchant"
