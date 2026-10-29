## An agent of the Coal Vetch on the dungeon grid, hunting the player.
##
## It reuses everything a rival group is on the map — it occupies a tile, takes a turn after the
## player's, falls to traps, answers to the staircase code — and replaces what a rival decides:
## no sight, no memory, no wandering. Each turn it takes one step along the SHORTEST path to the
## player, found by [method TileSearch.shortest_path], across floors by staircase. It sees through
## stealth (fog mantel, torment veil, a costume): it is not a spirimonster hunting by sight.
##
## Meeting the player ends the chase rather than opening an encounter, since an agent is no
## species and there is no encounter to open: see [method DungeonManager.agent_reached_player].
## Nothing bars it but walls, closed gateways, a rival in the way (it waits a turn), and safe
## areas, which keep it out like any rival; with no path it waits where it stands.
##
## No `class_name` (the CLI class-cache trap): preloaded. It extends [RivalBehavior] by path.
extends "res://scripts/exploration/rival_behavior.gd"

## The species slug of its single stand-in member. It is no species, and has no data.
const IDENTITY := &"coal_vetch"

## An agent that has just arrived does not move on the turn of its arrival.
var _fresh := true


func _ready() -> void:
	super()
	_add_marker()


## Always true: what tells an agent from a rival group, for the queries that want groups only
## ([method DungeonManager.rivals]).
func is_coal_vetch_agent() -> bool:
	return true


## A dark red post, until the agents have art.
func _add_marker() -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.5, 0.9, 0.5)
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.05, 0.08)
	mi.material_override = mat
	mi.position.y = 0.45
	add_child(mi)


## One step towards the player. See the class comment.
func take_turn(player_tile: Vector3i) -> void:
	if _busy or _dungeon == null:
		return
	if _fresh:
		_fresh = false
		return
	if tile == player_tile:
		_dungeon.agent_reached_player(self)
		return
	var path := _dungeon.tile_search.shortest_path(tile, player_tile, true)
	if path.size() < 2:
		return
	var next := path[1]
	var delta := next - tile
	if delta.y == 0 and absi(delta.x) + absi(delta.z) == 1:
		if next == player_tile:
			_dungeon.agent_reached_player(self)
			return
		if _dungeon.move_occupant(tile, next, self):
			await _step_to(next)
			if _dungeon == null:
				return
			_dungeon.notify_entered(next, self)
		return
	# Not a neighbour: a staircase from here leads there.
	for m in _dungeon.get_children():
		if (
			m.has_method("has_level_link")
			and m.has_level_link()
			and m.level_link_from() == tile
			and m.level_link_to() == next
		):
			await _use_level_link(m)
			return
