## Self-Disclosure — vilgane · [recover ETH]
## MÉCANIQUE : un total d'ETH (proportionnel au nombre de capacités utilisées par le user
## durant la rencontre) est partagé équitablement entre tous les individus. (Compteur de
## capacités utilisées : TODO → montant fixe par individu pour l'instant.)
extends AbilityScript

func execute(ctx: EncounterContext) -> void:
	for f in ctx.all_fighters:
		if not f.is_dissolved():
			ctx.recover_eth(f, ctx.dmg(&"small"))
