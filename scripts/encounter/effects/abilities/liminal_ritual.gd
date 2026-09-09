## Liminal Ritual — lulupéa · Variable · usage unique · [change weakness, recover DEN]
## MÉCANIQUE : utilisable seulement s'il existe un individu sans faiblesse. Tous les
## individus sans faiblesse regagnent X DEN et reçoivent la faiblesse de l'énergie de cette
## capacité (jusqu'à la fin de la rencontre, sauf changement par une autre capacité).
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var no_weakness := ctx.all_fighters.filter(
		func(f): return not f.is_dissolved() and ctx.weakness_of(f) == GameEnums.Energy.NONE
	)
	if no_weakness.is_empty():
		return
	for f in no_weakness:
		ctx.recover_den(f, ctx.dmg(&"normal"))
		ctx.set_weakness(f, ctx.energy())
