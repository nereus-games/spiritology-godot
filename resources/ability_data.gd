## Schéma d'une capacité (Talent, Exploration ou Rencontre).
##
## Instances stockées en .tres texte dans `data/abilities/`, ÉDITÉES À LA MAIN : ces
## fichiers sont la source de vérité, pas un artefact. Le design vit dans Notion et la
## correspondance champ par champ est documentée dans `docs/data-model.md` ; c'est
## `scripts/dev/data_integrity_check.gd` qui garantit leur cohérence.
## Les textes affichables passent par des clés de traduction, jamais en dur.
class_name AbilityData
extends Resource

## Identifiant slug stable (ex. "ghosting", "tumult"). Sert de nom de fichier et de
## base aux clés de traduction : ABILITY_<SLUG_MAJ>_NAME / _DESC.
@export var id: StringName

## Type de capacité. Conditionne les champs pertinents (un Talent n'a ni coût ni énergie).
@export var type: GameEnums.AbilityType = GameEnums.AbilityType.ENCOUNTER

## Espèce d'origine (slug, ex. "draka"). Vide si la capacité n'a pas d'origine
## (certaines capacités d'exploration). Réfère un [SpeciesData] via [GameData].
@export var origin_species: StringName

## Énergie de la capacité (rencontre). NONE pour talents et exploration.
@export var energy: GameEnums.Energy = GameEnums.Energy.NONE

## Coût en ETH (rencontre).
@export var cost: GameEnums.Cost = GameEnums.Cost.NONE

## Dégâts de base avant modificateurs. -1 = aucun dégât direct (effet pur).
## Les modificateurs (+36 % par condition : faiblesse, même Spiricosme, encyclopédie
## à 100 %, même espèce) sont cumulatifs et arrondis au supérieur, calculés à l'exécution.
@export var base_damage: int = -1

## Usage unique par rencontre / par visite de donjon selon le type.
@export var single_use: bool = false

## Tags décrivant les effets (ex. "ETH loss", "change weakness", "damage").
## Sert au moteur d'effets et au filtrage UI.
@export var tags: PackedStringArray = PackedStringArray()

## Chiffrage des paliers de coût. PLACEHOLDER (même statut que EncounterContext.DMG) :
## Notion ne décrit le coût que qualitativement (MINI/NORMAL/MEDIUM/A_LOT). Repère :
## EncounterFighter.BASE_ETH = 50, soit ~8 capacités NORMAL ou ~3 A_LOT par rencontre.
const COST_ETH := {
	GameEnums.Cost.NONE: 0,
	GameEnums.Cost.MINI: 3,
	GameEnums.Cost.NORMAL: 6,
	GameEnums.Cost.MEDIUM: 10,
	GameEnums.Cost.A_LOT: 15,
}

## Coût en ETH de la capacité (0 si gratuite). Payé à l'usage par le [EncounterManager].
func eth_cost() -> int:
	return COST_ETH.get(cost, 0)

## Clé de traduction du nom. Convention : ABILITY_<ID_MAJ>_NAME.
func name_key() -> String:
	return "ABILITY_%s_NAME" % GameEnums.key_token(id)

## Clé de traduction de la description. Convention : ABILITY_<ID_MAJ>_DESC.
func desc_key() -> String:
	return "ABILITY_%s_DESC" % GameEnums.key_token(id)
