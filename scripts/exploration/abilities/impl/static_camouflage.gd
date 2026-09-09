## Static Camouflage — se figer en objet pour observer les groupes de rivaux errants.
##
## Doc Notion : transformation temporaire en objet immobile ; 2 à 4 groupes de rivaux sont
## montrés un par un, le joueur choisit d'en affronter un ou d'attendre le suivant ; chances
## accrues d'espèces inconnues/variations près d'une litière.
##
## ## TODO: la révélation/choix de groupes dépend d'un système de spawn de groupes de rivaux
## (absent). Version minimale : passe le joueur en état de guet caché (voir
## [method ExplorationContext.scout_groups]).
extends "res://scripts/exploration/abilities/exploration_ability.gd"

func use(ctx) -> bool:
	ctx.scout_groups()
	return true
