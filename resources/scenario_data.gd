## Fiche d'un scénario de test d'exploration : ce que l'écran de sélection affiche.
##
## Instances .tres dans `data/scenarios/`, éditées à la main. Ne contient QUE le texte —
## identifiant, titre, et ce qu'il faut observer une fois dedans. La construction du
## donjon, elle, reste du code : `ScenarioCatalog` a un constructeur par scénario, et
## [member id] est ce qui relie les deux.
##
## Séparé du catalogue pour que ces textes soient modifiables sans toucher au code, et
## parce qu'ils relèvent du level design : ils sont sous licence de CONTENU, comme tout
## ce qui vit dans `data/` (cf. REUSE.toml).
class_name ScenarioData
extends Resource

## Identifiant du scénario. Doit correspondre à un cas de [method ScenarioCatalog.build].
@export var id: StringName

## Rang dans l'écran de sélection. Les scénarios sont rangés du plus simple au plus
## complet ; le dossier, lui, se lit par ordre alphabétique, d'où ce champ.
@export var order: int = 0

## Libellé du bouton.
@export var title: String = ""

## Ce qu'il faut observer une fois dans le scénario — le mode d'emploi du test.
@export_multiline var description: String = ""
