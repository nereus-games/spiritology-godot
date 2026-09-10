## Retroflection — forlorn akturlin · Arcane · mini/normal · [change weakness, damage, recover ETH]
## MECHANIC: damages the user — mini on the first use, normal afterwards — refills its ETH, and
## has it pick a weakness out of 3 random ones.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	ctx.deal_damage(ctx.user, ctx.dmg(&"mini"))  # TODO: normal on every later use
	ctx.recover_eth(ctx.user, ctx.user.max_eth)
	ctx.change_weakness(ctx.user)  # a random weakness, picked automatically among 3
