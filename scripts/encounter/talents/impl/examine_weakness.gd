## Examine Weakness (gélmi) — « If character uses an ability that touches its target's
## current weakness, they get a little info on target. If character is targeted by an
## Ability that touches their current weakness, they get a little info on the Ability's user. »
##
## Le hook [method on_weakness_touched] est appelé par le manager quand une capacité touche
## une faiblesse active impliquant le porteur (comme attaquant OU comme cible). L'EFFET —
## gagner « un peu d'info » sur l'autre — relève de l'encyclopédie-en-combat, système non
## bâti : STUB journalisé, à raffiner quand le gain d'info d'Examine existera (même statut
## que EncounterContext.grant_examine_bonus).
extends "res://scripts/encounter/talents/talent_script.gd"


func on_weakness_touched(manager, attacker, defender, _ability) -> void:
	var other = null
	if attacker == owner:
		other = defender  # info sur la cible
	elif defender == owner:
		other = attacker  # info sur l'utilisateur de la capacité
	else:
		return
	if other == null:
		return
	# TODO: octroyer un fragment d'info encyclopédie sur `other` quand ce système existera.
	manager.note_talent(
		"%s : info glanée sur %s (faiblesse touchée) [à venir]." % [_label(), other.display_name()]
	)


func _label() -> String:
	return String(TranslationServer.translate(talent.name_key())) if talent else "Examine Weakness"
