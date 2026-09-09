## Sublimation — forlorn jézal · Variable · [change next TO]
## MÉCANIQUE : choisir sa position au prochain tour (1re, 2e, ou après tous les alliés).
## Politique auto : se placer en tête.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	ctx.move_to_first(ctx.user)
