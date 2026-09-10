## Isotropy — firulis · [damage reduction/immunity]
## MECHANIC: until its next turn the user can neither lose nor gain DEN, and its weakness cannot
## be changed: it stays the current one whatever position it holds.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	ctx.set_weakness(ctx.user, ctx.weakness_of(ctx.user))  # fige la faiblesse actuelle
	ctx.lock_weakness(ctx.user)
	ctx.lock_den(ctx.user)
