## Fog Mantel — Exploration · from — · — · cost — · damage — · single use
##
## MECHANIC (from the design doc):
##   📖
##   In-game description:Become invisible from rivals for 5 to 8 tiles. Traps and encounters
##   cancel this invisibility.
##   Player character becomes invisible from rivals for 5 to 8 tiles. The number of tiles is
##   picked at random each time this is used.
##   Encounters and trap activations before the effect ends ends it immediately.
##
## An exploration ability: it is never used inside an encounter, so this script has nothing to
## run. The mechanic lives in `scripts/exploration/abilities/impl/fog_mantel.gd`: it hides the
## player for a random 5 to 8 tiles, and a sprung trap or an encounter clears it at once.
extends AbilityScript


func execute(_ctx: EncounterContext) -> void:
	pass
