## Fog Mantel — invisible to the rivals for a random 5 to 8 tiles.
##
## The design doc: "Become invisible from rivals for 5 to 8 tiles. Traps and encounters cancel
## this invisibility." The number of tiles is rolled on every use; an encounter or a sprung trap
## clears it at once, which the player and the trap handle.
extends "res://scripts/exploration/abilities/exploration_ability.gd"


func use(ctx) -> bool:
	ctx.hide_from_rivals(ctx.rng.randi_range(5, 8))
	return true
