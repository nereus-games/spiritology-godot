## Outlet Note — érzélak · Fluid · medium · single use · [limit actions, recover DEN]
## MECHANIC: a target on the team recovers all its DEN; the user can only use Meditate next
## turn.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var t = ctx.user  # a target on the team
	ctx.recover_den(t, t.max_den)
	ctx.restrict_to(ctx.user, ["UI_ENCOUNTER_ACTION_MEDITATE"])
