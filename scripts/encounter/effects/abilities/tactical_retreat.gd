## Tactical Retreat — akturlin · Crystal · [change next TO, redirect next damage received]
## MECHANIC: the user moves last next turn; Arcane damage it takes is converted into ETH until
## its next turn. The conversion is approximated by immunity.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	ctx.move_to_last(ctx.user)
	ctx.grant_immunity(ctx.user, [GameEnums.Energy.ARCANE])
	# TODO: convert the Arcane damage avoided into ETH.
