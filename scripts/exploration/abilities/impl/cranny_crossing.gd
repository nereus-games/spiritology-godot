## Cranny Crossing — traverse un mur fissuré d'une case d'épaisseur.
##
## Doc Notion : « Pass through a wall. Allows players to go through a cracked wall once and
## appear on the other side in a single move. » S'applique au mur fissuré ([Trap]/CrackedWall)
## présent sur la case regardée. Retourne false s'il n'y a pas de mur fissuré en face (rien
## n'est consommé). La traversée elle-même marque la capacité comme utilisée (via le mur).
extends "res://scripts/exploration/abilities/exploration_ability.gd"

func use(ctx) -> bool:
	return ctx.cross_faced_cracked_wall()
