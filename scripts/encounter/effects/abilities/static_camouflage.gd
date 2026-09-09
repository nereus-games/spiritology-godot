# @unimplemented
## Static Camouflage — Exploration · origine — · — · coût — · dégâts —
##
## MÉCANIQUE (Notion) :
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
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	# TODO: implémenter la mécanique ci-dessus, puis retirer le « @unimplemented »
	# en tête. En attendant, les effets génériques dérivés des tags s'appliquent —
	# c'est un échafaudage, pas la mécanique réelle.
	super.execute(ctx)
