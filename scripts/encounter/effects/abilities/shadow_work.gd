## Shadow Work — spodra · Arcane · a lot · usage unique · [examine bonus, recover ETH]
## MÉCANIQUE : (pas au 1er tour) le user obtient de l'info sur toutes les espèces de la
## rencontre ; il gagne X ETH si sa faiblesse est Arcane ou cachée aux rivaux.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	for f in ctx.all_fighters:
		if not f.is_dissolved():
			ctx.grant_examine_bonus(f, 1)
	if ctx.weakness_of(ctx.user) == GameEnums.Energy.ARCANE or ctx.user.weakness_hidden:
		ctx.recover_eth(ctx.user, ctx.dmg(&"normal"))
