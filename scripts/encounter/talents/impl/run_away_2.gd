## Run Away 2 (zuk) — "Run Away replaces Talk for this character. This character can't use
## Talk, but gets an extra action in encounters: Run Away. Unlike Slick Merchant, this
## version succeeds at all time and doesn't require any QTE."
##
## Expressed as a MENU mutation: Talk removed, Run Away (FLEE) added, permanently. Unlike
## slick_merchant, with no condition, no cost and no QTE.
##
## Two known wiring dependencies, shared by everything on the fleeing side:
##  1. the player menu and the agent have to CONSULT [method modify_menu], which is not wired yet;
##  2. actually leaving the encounter needs the exploration teleport (3-5 tiles, a 50% chance the
##     rival disappears), which is not built; resolving FLEE is a stub.
extends "res://scripts/encounter/talents/talent_script.gd"


func modify_menu(_manager, kinds: Array) -> void:
	kinds.erase(EncounterAction.Kind.TALK)
	if not kinds.has(EncounterAction.Kind.FLEE):
		kinds.append(EncounterAction.Kind.FLEE)
