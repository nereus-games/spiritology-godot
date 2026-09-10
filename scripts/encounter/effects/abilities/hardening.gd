## Hardening — firulis · Crystal · normal · [damage reduction/immunity]
## MECHANIC: a target on the team becomes immune to Crystal damage and has all damage it takes
## halved until its next turn. The info penalty on Talk is a TODO.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var t = ctx.user
	ctx.grant_immunity(t, [GameEnums.Energy.CRYSTAL])
	ctx.modify_damage(t, 0.5)
