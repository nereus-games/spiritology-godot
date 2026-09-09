## Black Soaking — forlorn malcouli · Arcane · normal · [change weakness, immunity]
## MÉCANIQUE : le user choisit une nouvelle faiblesse (parmi 3 au hasard) pour ce tour et
## le suivant ; il est immunisé aux dégâts Arcane jusqu'à son prochain tour.
extends AbilityScript

func execute(ctx: EncounterContext) -> void:
	ctx.change_weakness(ctx.user)  # nouvelle faiblesse (sélection auto parmi 3)
	ctx.grant_immunity(ctx.user, [GameEnums.Energy.ARCANE])
