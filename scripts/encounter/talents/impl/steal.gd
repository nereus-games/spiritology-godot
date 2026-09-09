## Steal (granop) — « Steal replaces Talk for this character. This character can't use Talk,
## but gets an extra action in encounters: Steal. Using it takes an object from the target,
## but has a risk of a member of The Coal Vetch appearing in the encounter. If that member
## is present, Steal has a 50 % chance of failing. »
##
## Volet MENU (traité ici) : Talk retiré, Steal ajouté (cf. [constant EncounterAction.Kind.STEAL]).
## Volet RÉSOLUTION (stub côté manager) : prendre un objet à la cible suppose que les rivaux
## PORTENT des objets (pas de telle donnée), et l'apparition du Coal Vetch est un système
## inexistant (comme pour le double-Examine). Voir EncounterManager._resolve_steal.
extends "res://scripts/encounter/talents/talent_script.gd"

func modify_menu(_manager, kinds: Array) -> void:
	kinds.erase(EncounterAction.Kind.TALK)
	if not kinds.has(EncounterAction.Kind.STEAL):
		kinds.append(EncounterAction.Kind.STEAL)
