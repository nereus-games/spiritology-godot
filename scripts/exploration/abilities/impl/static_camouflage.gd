## Static Camouflage — hold still as an object to watch the wandering rival groups.
##
## From the design doc: a temporary transformation into a motionless object; 2 to 4 rival groups
## are shown one at a time, and the player picks one to face or waits for the next; unknown
## species and variations are likelier near litter.
##
## The reveal and the choice are [Scouting], started through
## [method ExplorationContext.scout_groups]. Forlorn shapes are likelier under it
## ([Scouting]); not stacking with a costume and unknown species are not built (see the TODO in
## [Scouting]).
extends "res://scripts/exploration/abilities/exploration_ability.gd"


func use(ctx) -> bool:
	ctx.scout_groups()
	return true
