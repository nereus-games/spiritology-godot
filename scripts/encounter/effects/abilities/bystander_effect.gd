## Bystander Effect — ravbak · Heat · medium · [change weakness, examine bonus, limit actions]
## MECHANIC: the user's weakness becomes Crystal and one of its actions, drawn at random, is
## unavailable next turn; the other individuals get far more information out of Talk and
## Examine until the user's next turn.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	ctx.set_weakness(ctx.user, GameEnums.Energy.CRYSTAL)
	ctx.limit_actions(ctx.user, 1)
	for o in ctx.others():
		ctx.grant_examine_bonus(o, 2)
