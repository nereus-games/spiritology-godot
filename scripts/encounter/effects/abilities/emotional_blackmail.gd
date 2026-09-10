## Emotional Blackmail — draka · Toxic · small (7) · [change weakness, damage, limit actions]
## MECHANIC: the user forces an action on the targeted rival, Talk or Give an object; if it
## refuses, it takes damage and no rival can see the user's or its teammates' weakness any more,
## which is also changed at random. Of the accept/refuse branch, only the refusal is
## implemented.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var t = ctx.primary()
	if t:
		ctx.deal_damage(t, ctx.base_damage())  # cas du refus
	for m in ctx.team():
		ctx.hide_weakness(m)
		ctx.change_weakness(m)
