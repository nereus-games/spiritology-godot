## Effet d'une capacité d'exploration (base).
##
## Équivalent exploration de [AbilityScript] : une sous-classe par capacité d'exploration
## dans `impl/<id>.gd`, surchargeant [method use] pour appliquer la mécanique via les
## primitives de [ExplorationContext]. Résolu par `exploration_ability_catalog.gd`.
##
## Pas de `class_name` (piège du cache CLI) : `extends`/`preload` par chemin.
extends RefCounted

## Applique l'effet de la capacité. Retourne true si la capacité a été effectivement utilisée
## (et doit donc être marquée comme consommée pour la visite). Défaut : rien.
func use(_ctx) -> bool:
	return false
