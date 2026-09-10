## Black Soaking — forlorn malcouli · Arcane · normal · [change weakness, immunity]
## MECHANIC: the user picks a new weakness from 3 random ones, for this turn and the next, and
## is immune to Arcane damage until its next turn.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	ctx.change_weakness(ctx.user)  # nouvelle faiblesse (sélection auto parmi 3)
	ctx.grant_immunity(ctx.user, [GameEnums.Energy.ARCANE])
