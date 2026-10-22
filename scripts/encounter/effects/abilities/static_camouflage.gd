## Static Camouflage — Exploration · from — · — · cost — · damage —
##
## MECHANIC (from the design doc):
##   📖
##   In-game description:Hide in location to see more creatures.
##   Temporary transformation into an immobile object. While transformed, a group of
##   spririmonsters is shown to player (their sprite is visible on-screen, so player can see
##   their exact number, species, etc.)
##   Player can choose to encounter this group or keep waiting.
##   If they wait, up to 3 other groups are shown to them (one at a time, same presentation,
##   same choice). There can be 2 to 4 groups total. If player kept waiting for all groups
##   (including the last), a message is shown to explain no other group will show up (”It
##   seems no other group is wandering here.”) and player returns to Exploration.
##   If player chooses to encounter one of the groups, the transformation is over and no
##   subsequent group is shown after encountering said group.
##   Each of these groups has X % chances (Y % if this ability is used while next to or on
##   litter) of including unknown species and variations (rare colours, Forlorn shape).
##
## An exploration ability: it is never used inside an encounter, so this script has nothing to
## run. The mechanic lives in `scripts/exploration/abilities/impl/static_camouflage.gd` and
## `scripts/exploration/scouting.gd`: it shows 2 to 4 groups of the map one at a time and offers
## to take each on. The unknown-species and Forlorn chances wait on the Forlorn individual.
extends AbilityScript


func execute(_ctx: EncounterContext) -> void:
	pass
