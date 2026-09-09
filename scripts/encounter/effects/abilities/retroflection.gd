## Retroflection — forlorn akturlin · Arcane · mini/normal · [change weakness, damage, recover ETH]
## MÉCANIQUE : inflige des dégâts au user (mini à la 1re utilisation, normal ensuite),
## lui refait le plein d'ETH et lui fait choisir une faiblesse parmi 3 au hasard.
extends AbilityScript

func execute(ctx: EncounterContext) -> void:
	ctx.deal_damage(ctx.user, ctx.dmg(&"mini"))  # TODO : normal aux utilisations suivantes
	ctx.recover_eth(ctx.user, ctx.user.max_eth)
	ctx.change_weakness(ctx.user)  # faiblesse au hasard (sélection auto parmi 3)
