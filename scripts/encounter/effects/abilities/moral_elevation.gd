## Moral Elevation — sopiark · normal (10) · single use · [change weakness, immunity, recover ETH]
## MECHANIC: usable only if someone recently helped a rival recover ETH or DEN, or gave it an
## object. The user refills its ETH, loses its weakness, and nobody can change that weakness
## until its next turn. The mutual-aid condition is a TODO.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	ctx.recover_eth(ctx.user, ctx.user.max_eth)
	ctx.remove_weakness(ctx.user)
	ctx.lock_weakness(ctx.user)
