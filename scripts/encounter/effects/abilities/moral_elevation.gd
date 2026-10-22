## Moral Elevation — sopiark · normal (10) · single use · [change weakness, immunity, recover ETH]
## MECHANIC: usable only if someone recently helped a rival recover ETH or DEN, or gave it an
## object. The user refills its ETH, loses its weakness, and nobody can change that weakness
## until its next turn.
##
## Read from the encounter history. A rival is an opponent of the user; "someone" is anybody but
## the rival itself, since recovering by oneself is not being helped; "recently" is this round or
## the one before. The recovery must have gained something — ETH or DEN already full is no help.
## Whoever helped counts, the user's own side as well as the rival's.
##
## Not being usable, it is greyed out in the menu and left alone by the automatic agent; used
## regardless, it does nothing.
extends AbilityScript


func is_usable(ctx: EncounterContext) -> bool:
	return ctx.history.side_helped_recently(not ctx.user.is_player)


func execute(ctx: EncounterContext) -> void:
	if not is_usable(ctx):
		ctx.note(String(TranslationServer.translate("LOG_CONDITION_UNMET")))
		return
	ctx.recover_eth(ctx.user, ctx.user.max_eth)
	ctx.remove_weakness(ctx.user)
	ctx.lock_weakness(ctx.user)
