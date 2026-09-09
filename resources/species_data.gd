## Schéma d'une espèce de spirimonstre.
##
## Instances .tres (texte) dans `data/species/`, éditées à la main d'après Notion
## (Story + Characters / Possible Encounters) — cf. `docs/data-model.md`, qui décrit
## quelle propriété Notion alimente quel champ. Données LÉGÈRES uniquement : tout est
## chargé au boot. Les sprites sont des CHEMINS String (pas des Texture2D exportés),
## sinon charger le .tres tirerait la texture en RAM ; ils sont préchargés par donjon.
class_name SpeciesData
extends Resource

## Identifiant slug = nom commun de l'espèce (ex. "kalilk", "érzélak").
## Noms communs : pas de majuscule, non traduits. Base des clés de trad.
@export var id: StringName

## Spiricosme d'origine. Intervient dans les modificateurs de dégâts.
@export var spiricosm: GameEnums.Spiricosm = GameEnums.Spiricosm.GLOOM

## Les 3 faiblesses selon la position dans l'ordre du tour. L'ordre pouvant être
## modifié en cours de rencontre, la faiblesse active change dynamiquement.
@export var weakness_first: GameEnums.Energy = GameEnums.Energy.NONE
@export var weakness_middle: GameEnums.Energy = GameEnums.Energy.NONE
@export var weakness_last: GameEnums.Energy = GameEnums.Energy.NONE

## Chance par défaut que l'espèce initie un dialogue en rencontre (le « Talk »),
## normalisée dans [0.0, 1.0] (« 30% » dans Notion → 0.30). Ce n'est qu'un défaut :
## la valeur effective est ensuite modulée par le PSY, les capacités et le level design.
## 0.0 = ne parle pas par défaut (espèces agressives / cellule Notion vide).
@export_range(0.0, 1.0) var talker_chance: float = 0.0

## L'espèce peut-elle rejoindre le duo / devenir coéquipière (colonne « Can join … » :
## relation non vide dans la fiche Notion → true).
@export var can_join: bool = false

## Talent passif de l'espèce (slug d'un [TalentData]).
@export var talent: StringName

## Capacités d'origine : celles que l'espèce « apporte » à l'encyclopédie.
@export var origin_abilities: Array[StringName] = []

## Capacités également utilisées par l'espèce mais dont elle n'est pas l'origine.
@export var also_used_abilities: Array[StringName] = []

## Capacités débloquées via l'encyclopédie, dans l'ordre de déblocage :
## [0] à 15 fragments, [1] à 30 fragments.
@export var encyclopaedia_abilities: Array[StringName] = []

## Capacité exclusive à la variante Forlorn (débloquée à 15 fragments de la page Forlorn).
@export var forlorn_ability: StringName

## Loot potentiel (slugs d'objets). À étoffer quand le système d'objets existera.
@export var loot: Array[StringName] = []

## Chemins des sprites (res://...). String volontairement, voir note d'en-tête.
@export_file("*.png") var sprite_idle: String = ""
@export_file("*.png") var sprite_forlorn: String = ""

## Renvoie la faiblesse active pour une position d'ordre du tour donnée.
func weakness_for(position: GameEnums.TurnPosition) -> GameEnums.Energy:
	match position:
		GameEnums.TurnPosition.FIRST:
			return weakness_first
		GameEnums.TurnPosition.MIDDLE:
			return weakness_middle
		GameEnums.TurnPosition.LAST:
			return weakness_last
	return GameEnums.Energy.NONE

## Clé de traduction du nom affichable. Convention : SPECIES_<ID_MAJ_ASCII>_NAME.
## Accents pliés en ASCII via GameEnums.key_token (ex. id « razél » →
## SPECIES_RAZEL_NAME), pour matcher les clés écrites dans les .po par le générateur.
func name_key() -> String:
	return "SPECIES_%s_NAME" % GameEnums.key_token(id)
