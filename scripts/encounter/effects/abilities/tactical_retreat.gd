## Tactical Retreat — akturlin · Crystal · [change next TO, redirect next damage received]
## MÉCANIQUE : le user passe dernier au tour suivant ; les dégâts Arcane qu'il reçoit sont
## convertis en gain d'ETH jusqu'à son prochain tour (conversion : approximée par immunité).
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	ctx.move_to_last(ctx.user)
	ctx.grant_immunity(ctx.user, [GameEnums.Energy.ARCANE])
	# TODO : convertir les dégâts Arcane évités en gain d'ETH.
