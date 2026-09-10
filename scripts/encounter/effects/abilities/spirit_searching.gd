## Spirit Searching — sopiark · usage unique · [limit actions]
## MECHANIC: the targeted rival can only use Talk, Examine and Meditate for the rest of the
## encounter — among the actions otherwise available to it.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var t = ctx.primary()
	if t:
		ctx.restrict_to(t, ["Talk", "Examine", "Meditate"])
