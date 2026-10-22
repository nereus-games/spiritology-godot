## Cranny Crossing — Exploration · from — · — · cost — · damage — · single use
##
## MECHANIC (from the design doc):
##   📖
##   In-game description:Pass through a wall.
##   Allows players to go through a cracked wall once and appear on the other side of that
##   wall in a single move. Said wall must be exactly 1 tile thick.
##   Resolved inline commentsBlock text: Allows players to go through a wall once and appear
##   on the other side of that wall in a single move. Said wall must be exactly 1 tile thick.
##   - NNéd J. Aug 2, 2025, 12:44 AM
##   @Alexandre Ultré need an update and a page link –see the Cracked Wall in Level Design
##   then Walls+Decor
##
## An exploration ability: the mechanic lives in
## `scripts/exploration/abilities/impl/cranny_crossing.gd` and in the cracked wall mechanism
## (`scripts/exploration/mechanisms/cracked_wall.gd`), which checks the one-tile thickness.
## The encounter menu only offers abilities of type ENCOUNTER, so this script is never run in
## an encounter and, if it ever were, it must do nothing — hence the explicit empty override
## rather than the generic effects derived from the tags.
extends AbilityScript


func execute(_ctx: EncounterContext) -> void:
	pass
