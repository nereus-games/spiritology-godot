## A spirimonster species.
##
## Instances live in `data/species/` and are hand-maintained from the design doc
## (Story + Characters / Possible Encounters); `docs/data-model.md` says which Notion
## property feeds which field. Light data only — all of it is loaded at boot.
##
## Sprites are String PATHS rather than exported Texture2D on purpose: an exported
## texture would be pulled into memory with the .tres itself. They are preloaded per
## dungeon instead.
class_name SpeciesData
extends Resource

## Slug, and the base of this species' translation keys. Species are common nouns:
## lowercase, and not translated — the accented display name lives in the .po files.
@export var id: StringName

## Spiricosm of origin. Sharing one with the target is a damage modifier condition.
@export var spiricosm: GameEnums.Spiricosm = GameEnums.Spiricosm.GLOOM

## The three weaknesses, one per position in the turn order. Since abilities can reorder
## the turn mid-encounter, which one is exposed changes as the encounter runs.
@export var weakness_first: GameEnums.Energy = GameEnums.Energy.NONE
@export var weakness_middle: GameEnums.Energy = GameEnums.Energy.NONE
@export var weakness_last: GameEnums.Energy = GameEnums.Energy.NONE

## How likely the species is to open a dialogue, normalised to [0.0, 1.0] ("30%" in the
## doc becomes 0.30). A default only: PSY, abilities and level design modulate it.
## 0.0 means it does not talk — the aggressive species, and anything the doc leaves blank.
@export_range(0.0, 1.0) var talker_chance: float = 0.0

## Whether the species can join the duo as a teammate.
@export var can_join: bool = false

## This species' passive talent. One per species, and the relation is 1:1 both ways —
## data_integrity_check enforces it.
@export var talent: StringName

## Abilities this species originates, and therefore contributes to the encyclopaedia.
@export var origin_abilities: Array[StringName] = []

## Abilities the species also uses without originating them.
@export var also_used_abilities: Array[StringName] = []

## Unlocked by filling the encyclopaedia, in order: [0] at 15 fragments, [1] at 30.
@export var encyclopaedia_abilities: Array[StringName] = []

## Exclusive to the Forlorn variant, at 15 fragments of its own page.
@export var forlorn_ability: StringName

## Objects this species may drop.
@export var loot: Array[StringName] = []

## Sprite paths. String rather than Texture2D — see the header note.
@export_file("*.png") var sprite_idle: String = ""
@export_file("*.png") var sprite_forlorn: String = ""


## The weakness exposed at a given position in the turn order.
func weakness_for(position: GameEnums.TurnPosition) -> GameEnums.Energy:
	match position:
		GameEnums.TurnPosition.FIRST:
			return weakness_first
		GameEnums.TurnPosition.MIDDLE:
			return weakness_middle
		GameEnums.TurnPosition.LAST:
			return weakness_last
	return GameEnums.Energy.NONE


## Translation key of the displayed name: SPECIES_<ID>_NAME, uppercased and folded to
## ASCII by [method GameEnums.key_token].
func name_key() -> String:
	return "SPECIES_%s_NAME" % GameEnums.key_token(id)
