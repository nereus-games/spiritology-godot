## Retroflection — forlorn akturlin · Arcane · mini/normal · [change weakness, damage, recover ETH]
## MECHANIC: damages the user — mini on the first use, normal afterwards — refills its ETH, and
## has it pick a weakness out of 3 random ones.
##
## The first use is the user's first of this ability in the encounter, from the history: another
## individual using its own Retroflection does not spend it.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var first: bool = ctx.history.times_used(ctx.user, ctx.ability.id) == 0
	ctx.deal_damage(ctx.user, ctx.dmg(&"mini" if first else &"normal"))
	ctx.recover_eth(ctx.user, ctx.user.max_eth)
	ctx.change_weakness(ctx.user)  # a random weakness, picked automatically among 3
