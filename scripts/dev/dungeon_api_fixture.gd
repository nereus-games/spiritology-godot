## Helpers for [code]dungeon_api_check.gd[/code]: a bare dungeon, and an actor reduced to what
## the dungeon asks of one.
extends RefCounted


## An actor standing on `tile`, as far as the dungeon can tell: a [code]tile[/code] and a
## [code]teleport_to[/code]. Parented to `host` so that it is freed with the check.
class Actor:
	extends Node
	var tile := Vector3i.ZERO

	func teleport_to(dest: Vector3i) -> void:
		tile = dest


## A dungeon with a `width` x `depth` floor at level 0, no player, nothing else, parented to
## `host`.
static func field(host: Node, width: int, depth: int) -> DungeonManager:
	var dm := DungeonManager.new()
	host.add_child(dm)
	for x in width:
		for z in depth:
			dm.add_floor(Vector3i(x, 0, z))
	return dm


static func actor(host: Node, tile: Vector3i) -> Actor:
	var a := Actor.new()
	a.tile = tile
	host.add_child(a)
	return a
