## Shadow Work — spodra · Arcane · a lot · single use · [examine bonus, recover ETH]
## MECHANIC: not on turn 1. The user gets info on every species in the encounter, and gains X ETH
## if its weakness is Arcane or hidden from the rivals.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	for f in ctx.all_individuals:
		if not f.is_dissolved():
			ctx.grant_examine_bonus(f, 1)
	if ctx.weakness_of(ctx.user) == GameEnums.Energy.ARCANE or ctx.user.weakness_hidden:
		ctx.recover_eth(ctx.user, ctx.dmg(&"normal"))
