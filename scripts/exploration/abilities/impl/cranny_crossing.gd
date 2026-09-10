## Cranny Crossing — go through a cracked wall one tile thick.
##
## The design doc: "Pass through a wall. Allows players to go through a cracked wall once and
## appear on the other side in a single move." Applies to the cracked wall on the tile being
## faced. Returns false when there is none there, and nothing is spent. The crossing itself marks
## the ability as used, through the wall.
extends "res://scripts/exploration/abilities/exploration_ability.gd"


func use(ctx) -> bool:
	return ctx.cross_faced_cracked_wall()
