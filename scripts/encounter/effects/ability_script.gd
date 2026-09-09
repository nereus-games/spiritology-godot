## Orchestrateur de l'effet complet d'UNE capacité (logique unique).
##
## Chaque capacité a son script dédié dans `effects/abilities/<id>.gd`, généré depuis
## Notion (mécanique en docstring) et JAMAIS écrasé. Tant qu'une capacité n'est pas
## implémentée à la main, son script garde le comportement par défaut ci-dessous :
## exécuter les effets génériques dérivés des `tags` (briques [AbilityEffect]). Une
## capacité implémentée surcharge [method execute] avec sa mécanique précise (souvent
## conditionnelle : cibles, faiblesses, ordre du tour, UI…), en composant les briques
## [AbilityEffect] et/ou en appelant directement les helpers de l'[EncounterContext].
class_name AbilityScript
extends RefCounted

## Applique l'effet complet de la capacité à la rencontre.
## Défaut = comportement générique par tags ; à surcharger pour la mécanique propre.
func execute(ctx: EncounterContext) -> void:
	for effect in EffectCatalog.tag_effects(ctx.ability.tags):
		effect.execute(ctx)
