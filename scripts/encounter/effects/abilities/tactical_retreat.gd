## Tactical Retreat — akturlin · Crystal · [change next TO, redirect next damage received]
## MECHANIC: the user moves last next turn; Arcane damage it takes is converted into ETH until
## its next turn.
##
## The doc gives no rate, so each point of DEN avoided is one point of ETH gained, after every
## damage modifier. Damage the user takes in another energy is taken as usual.
extends AbilityScript

const OneOffs := preload("res://scripts/encounter/effects/one_off_rules.gd")


func execute(ctx: EncounterContext) -> void:
	ctx.move_to_last(ctx.user)
	OneOffs.convert_damage_to_eth(ctx, ctx.user, [GameEnums.Energy.ARCANE])
