## Reappraisal — hibulus · Arcane · [change weakness, recover ETH]
## MECHANIC: unusable on turn 1. The user's weakness is hidden from the rivals until its next
## turn; it picks a new weakness out of 2, hidden and stable; and it gains X ETH.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	ctx.hide_weakness(ctx.user)
	ctx.change_weakness(ctx.user)
	ctx.recover_eth(ctx.user, ctx.dmg(&"small"))
