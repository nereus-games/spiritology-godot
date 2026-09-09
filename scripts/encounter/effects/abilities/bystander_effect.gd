## Bystander Effect — ravbak · Heat · medium · [change weakness, examine bonus, limit actions]
## MÉCANIQUE : la faiblesse du user devient Cristal et une de ses actions au hasard est
## indisponible au prochain tour ; les autres individus obtiennent beaucoup plus d'info avec
## Parler et Examiner jusqu'au prochain tour du user.
extends AbilityScript

func execute(ctx: EncounterContext) -> void:
	ctx.set_weakness(ctx.user, GameEnums.Energy.CRYSTAL)
	ctx.limit_actions(ctx.user, 1)
	for o in ctx.others():
		ctx.grant_examine_bonus(o, 2)
