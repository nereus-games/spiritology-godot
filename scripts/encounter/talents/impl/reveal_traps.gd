## Reveal Traps (razél) — "When entering a dungeon level, reveals the position of the 3
## closest traps. When a chest attempts to teleport players, they can decide to teleport or
## not (the chest still gives ≥1 object, more if they teleport)."
##
## A wholly EXPLORATION talent: it has NO effect in an encounter, so it overrides no hook here.
## Both its clauses live on the dungeon side and are read through
## [method GameSession.party_has_talent] — outside an encounter there is no [EncounterIndividual] to
## carry this script:
##  - the CHEST clause is implemented in `mechanisms/chest.gd`: teleport or stay, with loot either
##    way;
##  - the TRAP clause is not: the 3 nearest traps are still not revealed on entering a floor.
##    The minimap already draws a trap once [member Trap.revealed]; nothing calls
##    [method Trap.reveal] (see the missing reveal phase in [method DungeonManager.advance_turn]).
extends "res://scripts/encounter/talents/talent_script.gd"
