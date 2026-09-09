## Reconnaissance Glide (ravbak).
##
## Volet RENCONTRE (traité ici) — « Examine (if used by this character) gets 10 % more
## info on target » : via [method modify_examine_info]. La magnitude d'un Examine n'est pas
## chiffrée (le gain d'info d'Examine n'est pas bâti), donc l'effet reste un facteur
## journalisé tant que ce système n'existe pas — STUB honnête, mais le hook est branché.
##
## Volet EXPLORATION (NON traité ici — attend le framework de donjon) — « Falling doesn't
## deal any damage to player characters » : les chutes appartiennent aux mécanismes de donjon.
extends "res://scripts/encounter/talents/talent_script.gd"

const EXAMINE_INFO_BONUS := 0.10  ## +10 % (valeur Notion), appliqué au gain de base.

func modify_examine_info(_manager, _target, base: float) -> float:
	return base * (1.0 + EXAMINE_INFO_BONUS)
