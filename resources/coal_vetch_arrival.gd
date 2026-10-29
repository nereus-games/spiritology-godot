## One arrival of a Coal Vetch agent in a dungeon, as level design writes it: where, and when.
##
## Hand-placed and hand-timed, like [member DungeonConfig.fixed_groups]: the point is a tile of
## the dungeon, and the turn is counted from the start of the visit, the unit the rest of the
## map keeps time in. See [member DungeonConfig.coal_vetch_arrivals].
class_name CoalVetchArrival
extends Resource

## The arrival point. If a rival stands on it, the agent appears on the nearest free tile.
@export var tile: Vector3i = Vector3i.ZERO

## The turn of the visit at which the agent arrives, 1 or more. A corrupted agent pushes it back
## by [member BalanceData.coal_vetch_delay_turns].
@export var turn: int = 1
