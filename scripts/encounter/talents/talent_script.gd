## Base d'un talent : passif d'espèce branché sur la boucle de rencontre.
##
## Analogue à [AbilityScript], mais ÉVÉNEMENTIEL. Une capacité s'exécute en un point
## UNIQUE (au moment de l'usage, via [method AbilityScript.execute]). Un talent, lui,
## RÉAGIT à des événements dispersés dans la boucle — début/fin de rencontre, Talk
## résolu, capacité consommée, menu construit. D'où un jeu de HOOKS plutôt qu'un seul
## `execute`. Chaque talent a son script dédié dans `talents/impl/<id>.gd` qui SURCHARGE
## les seuls hooks qui le concernent ; tous les autres restent no-op ici.
##
## Le manager collecte un [TalentScript] par combattant porteur (cf. son `_collect_talents`)
## et appelle ces hooks aux points de la boucle. Le `manager` ([EncounterManager]) est passé
## à chaque hook : il expose l'état et les helpers (allies_of/opponents_of, timeline, rng…).
##
## PAS de `class_name` : script neuf, donc absent de `.godot/global_script_class_cache.cfg`
## (que seul l'éditeur régénère). Comme le jeu se lance en CLI, un `class_name` neuf sortirait
## « Identifier not declared ». On l'obtient par `preload` chez l'appelant, et les impl
## étendent par CHEMIN (`extends "res://.../talent_script.gd"`).
extends RefCounted

## Talent source (données générées depuis Notion) — posé par [TalentCatalog].
var talent: TalentData
## Combattant qui porte ce talent. Les hooks « pour ce personnage » comparent à lui.
var owner: EncounterFighter
## Nombre d'exemplaires du talent dans l'ÉQUIPE du porteur (duo de même espèce). 1 par
## défaut ; >1 seulement si [member TalentData.stacks_in_duo]. Les talents à effet d'équipe
## peuvent s'en servir pour cumuler ; les talents par-personnage l'ignorent.
var stacks := 1

# --- Cycle de vie ---

## Début de rencontre (avant la 1re ronde). Point des mises en place (révélations donjon…).
func on_encounter_start(_manager) -> void:
	pass

## Fin de rencontre. `result` = &"victory" / &"defeat" / &"timeout".
func on_encounter_end(_manager, _result: StringName) -> void:
	pass

# --- Talk ---

## Ajuste la probabilité qu'un Talk soit « effectif ». Appelé pour chaque talent du camp
## du `speaker`, avec la chance de base (proxy `talker_chance` de la cible). Renvoyer la
## valeur ajustée (Slick Merchant : +15 % sur les 3 premiers tours).
func modify_talk_chance(_manager, _speaker, _target, base: float) -> float:
	return base

## Après qu'un Talk du camp du porteur a été résolu. `speaker` a parlé à `target` ;
## `effective` dit si le dialogue a porté. Serene Waves (parler à l'équipier → soin +
## retrait de faiblesse), Slick Merchant (Talk change la faiblesse du rival).
func on_talk_resolved(_manager, _speaker, _target, _effective: bool) -> void:
	pass

## Le porteur peut-il engager Talk avec un ÉQUIPIER (et pas seulement un rival) ? Le menu
## ajoute alors les alliés vivants aux cibles de Talk. Serene Waves (spodra) : oui — parler
## à l'équipier le revitalise. Défaut : non (Talk ne vise que les rivaux).
func allows_ally_talk(_manager) -> bool:
	return false

# --- Capacités ---

## Après qu'une capacité à usage UNIQUE du porteur a été consommée : renvoyer true pour la
## rendre à nouveau disponible dans la rencontre (Reuse : 50 % de chance). Défaut false.
func wants_reuse(_manager, _user, _ability) -> bool:
	return false

# --- Faiblesse / Examine (gain d'info encyclopédie) ---

## Le porteur a touché / a été touché sur une faiblesse active via une capacité.
## Effet = gain d'info (encyclopédie-en-combat, système non bâti → journalisé).
func on_weakness_touched(_manager, _attacker, _defender, _ability) -> void:
	pass

## Ajuste le gain d'info d'un Examine du porteur (Recon Glide : +10 %). PLACEHOLDER —
## le système d'info d'Examine n'est pas chiffré.
func modify_examine_info(_manager, _target, base: float) -> float:
	return base

# --- Menu ---

## Mute la liste d'actions offertes au porteur. `kinds` = Array[EncounterAction.Kind]
## modifiable en place (Run Away remplace Talk ; Steal remplace Talk…). Le câblage
## UI/agent viendra dans un second temps ; le hook est défini pour que les talents
## l'expriment dès maintenant, et que le manager puisse le consulter.
func modify_menu(_manager, _kinds: Array) -> void:
	pass
