## Isotropy — firulis · [damage reduction/immunity]
## MÉCANIQUE : jusqu'à son prochain tour, le user ne peut perdre/gagner de DEN, sa
## faiblesse ne peut être changée et reste sa faiblesse actuelle (quelle que soit la position).
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	ctx.set_weakness(ctx.user, ctx.weakness_of(ctx.user))  # fige la faiblesse actuelle
	ctx.lock_weakness(ctx.user)
	ctx.lock_den(ctx.user)
