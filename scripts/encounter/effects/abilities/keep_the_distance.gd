## Keep the Distance — fonéchal · Crystal · normal · [change next TO, limit actions]
## MECHANIC: the user picks its own and the target's position next turn, one first and the other
## last. The automatic policy is user first, target last; the target can only use Meditate next
## turn.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var t = ctx.primary()
	ctx.move_to_first(ctx.user)
	if t:
		ctx.move_to_last(t)
		ctx.restrict_to(t, ["Meditate"])
