## Homeostasis — lulupéa · Crystal · [change next TO, recover ETH]
## MECHANIC: the user keeps its place in the turn order next turn, and gains X ETH every time an
## ability damages it, until its next turn. Keeping the position simply means reordering nothing;
## gaining the ETH at the moment of the damage is a TODO.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	# Keeping the position simply means requesting no reordering.
	ctx.recover_eth(ctx.user, ctx.dmg(&"small"))  # an approximation of the conditional gain
