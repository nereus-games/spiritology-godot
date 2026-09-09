## Restore (akturlin) — « After an encounter, player characters regain X % DEN and Y % ETH.
## Refresh crystals restore 100 % ETH. »
##
## En fin de rencontre, rend un pourcentage de DEN/ETH à l'équipe du porteur. Le manager
## mute directement les [EncounterFighter] joueurs ; l'UI de rencontre resynchronise ensuite
## ces valeurs vers l'état persistant [GameSession] (comme pour les dégâts subis). Le cumul
## en duo (deux akturlin) est naturel : un [TalentScript] par porteur → le hook s'applique
## une fois par exemplaire.
##
## Le volet « refresh crystals restore 100 % ETH » relève de l'EXPLORATION (cristaux de
## rafraîchissement = mécanisme de donjon non bâti) — hors de la rencontre, non traité ici.
extends "res://scripts/encounter/talents/talent_script.gd"

## PLACEHOLDERS — Notion écrit « X % DEN / Y % ETH » sans les chiffrer (même statut que les
## paliers d'ETH ou OBJECT_HEAL_DEN). À trancher en jouant.
const DEN_FRACTION := 0.2
const ETH_FRACTION := 0.35


func on_encounter_end(manager, result: StringName) -> void:
	# Pas de résurrection : sur une défaite, le duo est dissous, « après la rencontre » n'a
	# pas de sens. On ne rend que si l'équipe a survécu.
	if result == &"defeat":
		return
	for f in manager.allies_of(owner):
		if f.is_dissolved():
			continue
		f.recover_den(roundi(f.max_den * DEN_FRACTION))
		f.recover_eth(roundi(f.max_eth * ETH_FRACTION))
	manager.note_talent("%s : le duo récupère DEN/ETH en fin de rencontre." % _label())


func _label() -> String:
	return String(TranslationServer.translate(talent.name_key())) if talent else "Restore"
