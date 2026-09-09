## Reappraisal — hibulus · Arcane · [change weakness, recover ETH]
## MÉCANIQUE : (inutilisable au 1er tour). La faiblesse du user est cachée aux rivaux jusqu'à
## son prochain tour ; il choisit une nouvelle faiblesse parmi 2 (cachée et stable) ; +X ETH.
extends AbilityScript

func execute(ctx: EncounterContext) -> void:
	ctx.hide_weakness(ctx.user)
	ctx.change_weakness(ctx.user)
	ctx.recover_eth(ctx.user, ctx.dmg(&"small"))
