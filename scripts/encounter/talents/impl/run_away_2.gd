## Run Away 2 (zuk) — « Run Away replaces Talk for this character. This character can't use
## Talk, but gets an extra action in encounters: Run Away. Unlike Slick Merchant, this
## version succeeds at all time and doesn't require any QTE. »
##
## Traduit en mutation de MENU : Talk retiré, Run Away (FLEE) ajouté, en permanence.
## Contrairement à slick_merchant, sans condition ni coût ni QTE.
##
## Deux dépendances de câblage, connues et communes à tout le volet « fuite » :
##  1. le menu joueur / l'agent doivent CONSULTER [method modify_menu] (câblage à venir) ;
##  2. quitter réellement la rencontre suppose la téléportation en exploration (3-5 cases,
##     50 % que le rival disparaisse) — non bâtie ; la résolution de FLEE est un stub.
extends "res://scripts/encounter/talents/talent_script.gd"

func modify_menu(_manager, kinds: Array) -> void:
	kinds.erase(EncounterAction.Kind.TALK)
	if not kinds.has(EncounterAction.Kind.FLEE):
		kinds.append(EncounterAction.Kind.FLEE)
