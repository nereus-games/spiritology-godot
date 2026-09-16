## One individual of a PREDEFINED rival group, as level design writes it: a special composition,
## or a group placed by hand.
##
## Randomly composed groups do not use it — they are drawn from the bounds a [DungeonConfig]
## sets. Once a group is on the map, each of its members lives on as a `rival_member.gd`, which
## tracks the current DEN and ETH this only gives the maximum of.
class_name RivalMemberData
extends Resource

## The variety, as a species slug.
@export var species_id: StringName

@export var max_den: int = 50
@export var max_eth: int = 50
