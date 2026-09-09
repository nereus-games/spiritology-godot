## Classe de base d'un effet de capacité (unité scriptable).
##
## Chaque tag d'effet de la doc Notion (« damage », « change weakness », « recover ETH »…)
## a une sous-classe. Le registre [EncounterEffects] résout une [AbilityData] (générée
## depuis Notion) en une liste d'AbilityEffect d'après ses `tags`, avec surcharges
## sur-mesure pour les capacités à logique spéciale (Tumult, Anodyne Excess…).
## Les effets ne mutent rien directement : ils passent par l'[EncounterContext].
class_name AbilityEffect
extends RefCounted


## Tag Notion correspondant (cf. [member AbilityData.tags]).
func tag() -> StringName:
	return &""


## Applique l'effet à la rencontre. À surcharger.
func execute(_ctx: EncounterContext) -> void:
	pass
