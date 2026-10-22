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

## Rivals choosing an action "more often" (Radiant Secret, Hyping Up, Misty Secret, Business
## Card): a probability added to the chance of Talking, Meditating or using an object on a turn.
## The doc gives no figure, so the step the game already applies per condition stands in, as for
## [member meditate_damage_bonus]. One's Ethos does give one: "5 % more often".
@export var action_weight_bonus: float = 0.36
@export var ethos_talk_bonus: float = 0.05

## Running away from an encounter: "teleporting 3 to 5 tiles away", counted in steps actually
## walkable from where the encounter took place. Figures the doc gives.
@export var flee_distance_min: int = 3
@export var flee_distance_max: int = 5

## Turns a group still on the map stays put after an encounter, so that it does not open the
## next one straight away. The doc says nothing about it: a placeholder, see
## [method RivalBehavior.rest].
@export var rival_rest_turns: int = 3

## Rival spawning, where the doc leaves the figure open. A species is drawn with a weight by
## its rarity in the dungeon: rare 1, normal [member spawn_weight_normal], common
## [member spawn_weight_common]. The doc proposes 3 and 2 for common and normal, unanswered.
@export var spawn_weight_common: int = 3
@export var spawn_weight_normal: int = 2

## Spawn waves "should grow wider first" at a high PSY: above [member wave_psy_threshold], each
## wave brings [member wave_psy_extra_groups] more groups. The doc does not say how high is
## high; the figure borrows the decor's.
@export var wave_psy_threshold: int = 20
@export var wave_psy_extra_groups: int = 1

## Examining decor above [member decor_psy_threshold] PSY has a [member decor_spawn_chance]
## chance (the doc: PSY 20, 45 %) of bringing 1 to [member decor_spawn_groups_max] groups within
## [member decor_spawn_radius] tiles. The doc says "one or more" and "nearby": the last two
## figures are placeholders.
@export var decor_psy_threshold: int = 20
@export_range(0.0, 1.0) var decor_spawn_chance: float = 0.45
@export var decor_spawn_groups_max: int = 2
@export var decor_spawn_radius: int = 4

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
