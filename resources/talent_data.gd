## A Talent: a species' passive.
##
## One per species, neither learnable nor unlockable, and it stacks when the duo carries
## two individuals of the same species. Kept separate from [AbilityData] because talents
## have no energy, no cost and no direct damage, and obey an event-driven logic of their
## own ([TalentScript]).
##
## Instances live in `data/abilities/` alongside the abilities — in Notion they are one
## database, told apart by a Type column.
class_name TalentData
extends Resource

## Slug, and the base of this talent's translation keys.
@export var id: StringName

## The species carrying it. The relation is 1:1 both ways, and enforced by
## data_integrity_check.
@export var owner_species: StringName

## Coarse effect categories, as on [AbilityData].
@export var tags: PackedStringArray = PackedStringArray()

## Whether two copies of this talent in one duo are meant to add up.
@export var stacks_in_duo: bool = true


## Translation key of the name: TALENT_<ID>_NAME.
func name_key() -> String:
	return "TALENT_%s_NAME" % GameEnums.key_token(id)


## Translation key of the description: TALENT_<ID>_DESC.
func desc_key() -> String:
	return "TALENT_%s_DESC" % GameEnums.key_token(id)
