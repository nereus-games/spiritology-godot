## Homeostasis — lulupéa · Crystal · [change next TO, recover ETH]
## MECHANIC: the user keeps its place in the turn order next turn, and gains X ETH every time an
## ability damages it, until its next turn. Keeping the position simply means reordering nothing.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	ctx.watch_reactions()


func react(ctx: EncounterContext, event) -> void:
	if event.hurt(ctx.user):
		ctx.recover_eth(ctx.user, ctx.dmg(&"small"))
