## Unfocused Complaint — niyat · Toxic · a lot · small (7) · [ETH loss, damage, limit actions]
## MECHANIC: any other individual that uses Meditate this turn takes damage, loses X ETH, and
## cannot Meditate next turn. The "uses Meditate" trigger is approximated to everyone else for
## now, and should be narrowed once the action system exists.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	for o in ctx.others():
		ctx.deal_damage(o, ctx.base_damage())  # TODO: only if o Meditates this turn
		ctx.drain_eth(o, ctx.dmg(&"small"))
		ctx.restrict_to(o, ["LOG_RESTRICT_EXCEPT_MEDITATE"])
