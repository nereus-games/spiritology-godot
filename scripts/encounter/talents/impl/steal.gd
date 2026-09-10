## Steal (granop) — "Steal replaces Talk for this character. This character can't use Talk,
## but gets an extra action in encounters: Steal. Using it takes an object from the target,
## but has a risk of a member of The Coal Vetch appearing in the encounter. If that member
## is present, Steal has a 50 % chance of failing."
##
## The MENU half, handled here: Talk removed, Steal added (see
## [constant EncounterAction.Kind.STEAL]).
## The RESOLUTION half is a stub in the manager: taking an object off the target assumes rivals
## CARRY objects, and no such data exists, while the Coal Vetch appearing is a system that does
## not exist either (as with the double Examine). See EncounterManager._resolve_steal.
extends "res://scripts/encounter/talents/talent_script.gd"


func modify_menu(_manager, kinds: Array) -> void:
	kinds.erase(EncounterAction.Kind.TALK)
	if not kinds.has(EncounterAction.Kind.STEAL):
		kinds.append(EncounterAction.Kind.STEAL)
