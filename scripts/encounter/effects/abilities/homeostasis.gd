## Homeostasis — lulupéa · Crystal · [change next TO, recover ETH]
## MÉCANIQUE : le user conserve sa position dans l'ordre du tour au prochain tour ; il gagne
## X ETH chaque fois qu'il subit des dégâts d'une capacité, jusqu'à son prochain tour.
## (Maintien de position = ne rien réordonner ; gain d'ETH au moment des dégâts : TODO.)
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	# Conserve la position : aucune demande de réordonnancement.
	ctx.recover_eth(ctx.user, ctx.dmg(&"small"))  # approx. du gain conditionnel
