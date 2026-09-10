## Valeurs d'équilibrage de la rencontre, rassemblées en un seul endroit.
##
## Ce ne sont PAS des décisions prises dans le code : la doc Notion les écrit « X % » et
## « Y DEN », littéralement surlignées comme à faire. Elles ne peuvent être tranchées qu'en
## JOUANT. Éparpillées dans quatre fichiers, il fallait fouiller pour les régler ; ici, un
## seul fichier de données les porte, et l'ajustement ne demande plus de toucher au code.
##
## Instance unique : `data/balance.tres`, obtenue par [method current].
class_name BalanceData
extends Resource

## DEN et ETH de départ, identiques pour tout le monde.
## ## TODO: stats par espèce quand la doc les fournira.
@export var base_den: int = 100
@export var base_eth: int = 50

## Coût en ETH par palier. Notion ne décrit le coût que qualitativement (MINI/NORMAL/
## MEDIUM/A_LOT) — ces chiffres sont un calage : avec base_eth = 50, une rencontre offre
## ~8 capacités NORMAL ou ~3 A_LOT.
@export var cost_mini: int = 3
@export var cost_normal: int = 6
@export var cost_medium: int = 10
@export var cost_a_lot: int = 15

## Dégâts de base par palier, quand la capacité ne chiffre pas les siens.
@export var damage_mini: int = 5
@export var damage_small: int = 7
@export var damage_normal: int = 10
@export var damage_big: int = 14

## Pourcentage de dégâts ajouté par CONDITION remplie (faiblesse touchée, même Spiricosme,
## encyclopédie complétée, même espèce). Les conditions s'additionnent avant application.
@export var modifier_per_condition: float = 0.36

## Meditate : « recovers X ETH; damage +Y % until next turn ». Ni X ni Y ne sont chiffrés
## par la doc. Le bonus reprend le pas de +36 % déjà utilisé par le jeu.
@export var meditate_eth: int = 12
@export var meditate_damage_bonus: float = 0.36

## Rune stone : « gives Y DEN to a target ». Utilisé quand [member ObjectData.magnitude]
## vaut 0, c'est-à-dire tant que Notion écrit « Y DEN » plutôt qu'un nombre.
@export var object_heal_den: int = 25

const PATH := "res://data/balance.tres"

static var _current: BalanceData


## Instance partagée, chargée une fois. Statique parce que les appelants sont des
## RefCounted sans accès aux autoloads ([EncounterContext], [AbilityData]) : passer
## l'équilibrage de main en main jusqu'à eux aurait traversé tout le moteur de rencontre.
static func current() -> BalanceData:
	if _current == null:
		_current = load(PATH)
	return _current


## Coût en ETH d'un palier de [enum GameEnums.Cost].
func cost_eth(cost: GameEnums.Cost) -> int:
	match cost:
		GameEnums.Cost.MINI:
			return cost_mini
		GameEnums.Cost.NORMAL:
			return cost_normal
		GameEnums.Cost.MEDIUM:
			return cost_medium
		GameEnums.Cost.A_LOT:
			return cost_a_lot
	return 0


## Dégâts d'un palier nommé (« mini », « small », « normal », « big »).
func damage(tier: StringName) -> int:
	match tier:
		&"mini":
			return damage_mini
		&"small":
			return damage_small
		&"big":
			return damage_big
	return damage_normal
