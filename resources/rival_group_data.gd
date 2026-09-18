## A rival group whose composition level design decides, member by member.
##
## Two uses, both in [DungeonConfig]:
## - a SPECIAL composition, picked when a spawn does not draw its group at random. It appears on
##   one of the dungeon's spawn points, and [member tile] is ignored;
## - a FIXED group — a tutorial rival, a boss — which appears once, on [member tile], when the
##   dungeon is first entered.
class_name RivalGroupData
extends Resource

@export var members: Array[RivalMemberData] = []

## Where a fixed group appears. Ignored for a special composition.
@export var tile: Vector3i = Vector3i.ZERO
