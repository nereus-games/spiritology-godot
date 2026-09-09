## Reveal Traps (razél) — « When entering a dungeon level, reveals the position of the 3
## closest traps. When a chest attempts to teleport players, they can decide to teleport or
## not (the chest still gives ≥1 object, more if they teleport). »
##
## Talent 100 % EXPLORATION : il n'a AUCUN effet en rencontre, donc aucun hook n'est surchargé
## ici. Ses deux clauses vivent côté donjon, et sont lues via
## [method GameSession.party_has_talent] (hors rencontre, il n'existe aucun [EncounterFighter]
## pour porter ce script) :
##  - clause COFFRE : implémentée dans `mechanisms/chest.gd` (choix téléporter/rester, butin
##    dans les deux cas) ;
##  - clause PIÈGES : les 3 pièges les plus proches ne sont pas encore révélés à l'entrée d'un
##    étage — [member Trap.revealed] / [member Chest.revealed] existent, mais la carte ne
##    dessine pas encore les mécanismes (même chantier que `trick_to_reveal`).
extends "res://scripts/encounter/talents/talent_script.gd"
