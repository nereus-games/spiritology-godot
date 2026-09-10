## The encounter's balance figures, gathered in one place.
##
## None of these is a decision taken in code. The design doc writes them as "X %" and
## "Y DEN" — literally highlighted as outstanding — and they can only be settled by
## PLAYING. Scattered across four files they had to be hunted down to be tuned; here one
## data file carries them, and adjusting them needs no code at all.
##
## Single instance: `data/balance.tres`, reached through [method current].
class_name BalanceData
extends Resource

## Starting DEN and ETH, the same for everyone.
## ## TODO: per-species stats once the doc provides them.
@export var base_den: int = 100
@export var base_eth: int = 50

## ETH per cost tier. The doc only names the tiers; these figures are a calibration —
## with base_eth = 50, an encounter affords about eight NORMAL abilities or three A_LOT.
@export var cost_mini: int = 3
@export var cost_normal: int = 6
@export var cost_medium: int = 10
@export var cost_a_lot: int = 15

## Damage per tier, used when an ability states a tier but no number.
@export var damage_mini: int = 5
@export var damage_small: int = 7
@export var damage_normal: int = 10
@export var damage_big: int = 14

## Damage added per CONDITION met — weakness touched, shared Spiricosm, completed
## encyclopaedia page, same species. Conditions add up before being applied. The one
## figure the doc actually gives.
@export var modifier_per_condition: float = 0.36

## Meditate: "recovers X ETH; damage +Y % until next turn". Neither X nor Y is given;
## the bonus reuses the step the game already applies per condition.
@export var meditate_eth: int = 12
@export var meditate_damage_bonus: float = 0.36

## Rune stone: "gives Y DEN to a target". Used whenever [member ObjectData.magnitude] is
## 0, which is to say for as long as the doc writes "Y DEN" instead of a number.
@export var object_heal_den: int = 25

const PATH := "res://data/balance.tres"

static var _current: BalanceData


## The shared instance, loaded once.
##
## Static because the callers are RefCounted objects with no access to autoloads —
## [EncounterContext], [AbilityData] — and threading a balance object down to them would
## have run through the whole encounter engine.
static func current() -> BalanceData:
	if _current == null:
		_current = load(PATH)
	return _current


## ETH cost of a [enum GameEnums.Cost] tier.
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


## Damage for a named tier: "mini", "small", "normal", "big".
func damage(tier: StringName) -> int:
	match tier:
		&"mini":
			return damage_mini
		&"small":
			return damage_small
		&"big":
			return damage_big
	return damage_normal
