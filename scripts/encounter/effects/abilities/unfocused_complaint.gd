## Unfocused Complaint — niyat · Toxic · a lot · small (7) · [ETH loss, damage, limit actions]
## MECHANIC: any other individual that uses Meditate this turn takes damage, loses X ETH, and
## cannot Meditate next turn. "This turn" is until the user's next turn.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	ctx.watch_reactions()


func react(ctx: EncounterContext, event) -> void:
	if event.actor == ctx.user or not event.is_action_of(EncounterAction.Kind.MEDITATE):
		return
	ctx.deal_damage(event.actor, ctx.base_damage())
	ctx.drain_eth(event.actor, ctx.dmg(&"small"))
	ctx.restrict_to(event.actor, ["LOG_RESTRICT_EXCEPT_MEDITATE"])
