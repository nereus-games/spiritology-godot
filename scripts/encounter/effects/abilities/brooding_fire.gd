## Brooding Fire — fliritus · Heat · normal · [change weakness, recover DEN, recover ETH]
## MÉCANIQUE : le coéquipier perd sa faiblesse ; si la faiblesse du user est Chaleur,
## le coéquipier gagne X DEN et X ETH.
extends AbilityScript

func execute(ctx: EncounterContext) -> void:
	var heat := ctx.weakness_of(ctx.user) == GameEnums.Energy.HEAT
	for a in ctx.allies():
		ctx.remove_weakness(a)
		if heat:
			ctx.recover_den(a, ctx.dmg(&"normal"))
			ctx.recover_eth(a, ctx.dmg(&"normal"))
