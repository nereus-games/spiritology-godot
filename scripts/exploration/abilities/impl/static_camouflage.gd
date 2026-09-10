## Static Camouflage — hold still as an object to watch the wandering rival groups.
##
## From the design doc: a temporary transformation into a motionless object; 2 to 4 rival groups
## are shown one at a time, and the player picks one to face or waits for the next; unknown
## species and variations are likelier near litter.
##
## ## TODO: revealing and choosing groups needs a rival-group spawn system, which does not exist.
## Minimal version: puts the player into a hidden scouting state (see
## [method ExplorationContext.scout_groups]).
extends "res://scripts/exploration/abilities/exploration_ability.gd"


func use(ctx) -> bool:
	ctx.scout_groups()
	return true
