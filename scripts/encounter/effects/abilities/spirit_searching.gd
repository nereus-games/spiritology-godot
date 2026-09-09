## Spirit Searching — sopiark · usage unique · [limit actions]
## MÉCANIQUE : le rival ciblé ne peut utiliser que Parler, Examiner et Méditer jusqu'à la
## fin de la rencontre (parmi ses actions par ailleurs disponibles).
extends AbilityScript

func execute(ctx: EncounterContext) -> void:
	var t = ctx.primary()
	if t:
		ctx.restrict_to(t, ["Talk", "Examine", "Meditate"])
