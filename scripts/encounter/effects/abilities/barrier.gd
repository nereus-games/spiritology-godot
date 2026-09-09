## Barrier — razél · Crystal · medium · [damage reduction/immunity, recover ETH]
## MÉCANIQUE : une cible alliée (soi ou coéquipier) récupère X ETH ; les prochains dégâts
## Fluide, Toxique ou Cristal qui la touchent sont réduits de moitié.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var t = ctx.user  # soi par défaut (cible alliée)
	ctx.recover_eth(t, ctx.dmg(&"normal"))
	for e in [GameEnums.Energy.FLUID, GameEnums.Energy.TOXIC, GameEnums.Energy.CRYSTAL]:
		ctx.set_energy_damage_factor(t, e, 0.5)
