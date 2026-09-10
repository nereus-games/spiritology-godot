## An ability — Talent, Exploration or Encounter.
##
## Instances live in `data/abilities/` and are HAND-MAINTAINED: these files are the source
## of truth, not an artefact of anything. The design lives in Notion, the field-by-field
## correspondence is in `docs/data-model.md`, and `scripts/dev/data_integrity_check.gd` is
## what keeps them consistent. Displayed text always goes through translation keys.
class_name AbilityData
extends Resource

## Slug. Doubles as the filename and as the base of the translation keys.
@export var id: StringName

## Which fields matter: a Talent has neither cost nor energy.
@export var type: GameEnums.AbilityType = GameEnums.AbilityType.ENCOUNTER

## Species this ability originates from. Empty for the exploration abilities that have
## no origin.
@export var origin_species: StringName

## Energy, for encounter abilities. NONE for talents and exploration.
@export var energy: GameEnums.Energy = GameEnums.Energy.NONE

## Cost tier, for encounter abilities.
@export var cost: GameEnums.Cost = GameEnums.Cost.NONE

## Damage before modifiers. -1 means no direct damage at all — a pure-effect ability.
## The modifiers (one step per condition met: weakness touched, shared Spiricosm, completed
## encyclopaedia page, same species) add up and are rounded up at execution time.
@export var base_damage: int = -1

## Once per encounter, or per dungeon visit, depending on the type.
@export var single_use: bool = false

## Coarse effect categories. They drive the generic fallback in [EffectCatalog] and the
## UI filtering — they are a guard rail, never the real mechanic.
@export var tags: PackedStringArray = PackedStringArray()


## ETH cost, paid by [EncounterManager] before the effect runs. The figures behind the
## tiers live in `data/balance.tres`; the doc only names the tiers.
func eth_cost() -> int:
	return BalanceData.current().cost_eth(cost)


## Translation key of the name: ABILITY_<ID>_NAME.
func name_key() -> String:
	return "ABILITY_%s_NAME" % GameEnums.key_token(id)


## Translation key of the description: ABILITY_<ID>_DESC.
func desc_key() -> String:
	return "ABILITY_%s_DESC" % GameEnums.key_token(id)
