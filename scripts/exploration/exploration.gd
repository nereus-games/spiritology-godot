## Root of the exploration scene: 3D, and persistent.
##
## Connects the [DungeonManager]'s encounter request to opening an encounter as an additive
## OVERLAY through [TransitionManager] — exploration is paused, and stays visible behind. On a
## victory the rival is removed from the dungeon.
extends Node3D

const ScenarioCatalog := preload("res://scripts/dev/scenario_catalog.gd")

@onready var _dungeon: DungeonManager = $DungeonManager

var _pending_rival: Node

# --- Real-time narrow-bridge driver (per tile, in both directions) ---
var _active_bridge  ## the bridge tile in progress, or null
var _bridge_dir: Vector3i  ## direction of travel, as a tile delta
var _bridge_from: Vector3i  ## the tile the current advance started from
var _bridge_balance  ## the crossing's balance model, carried from tile to tile
var _in_bridge := false  ## a crossing is under way
## Maximum camera roll (degrees) at full imbalance — this is what losing your footing looks
## like.
const BRIDGE_ROLL_DEG := 28.0


func _ready() -> void:
	_dungeon.encounter_requested.connect(_on_encounter_requested)
	_dungeon.bridge_collision.connect(_on_bridge_collision)
	_dungeon.turn_advanced.connect(_on_turn_advanced)
	TransitionManager.encounter_finished.connect(_on_encounter_finished)
	GameSession.party_wiped.connect(_on_party_wiped)
	# Entering a dungeon fully restores the duo's ETH (the "Game Units" rule), and resets the
	# tracking of once-per-visit exploration abilities.
	GameSession.restore_party_eth()
	GameSession.reset_exploration_abilities()
	# DEV: builds the chosen test scenario (populating the grid and the session) and places the
	# player. Done LAST so that the state the scenario sets — objects, abilities marked as used —
	# is not wiped by the dungeon-entry logic above.
	var start: Vector3i = ScenarioCatalog.build(ScenarioCatalog.selected_id, _dungeon)
	# DEV: the player starts where they would enter the dungeon, which makes that tile the
	# entrance — and, per the design doc, an exit too. Mechanisms that send them back there, like
	# dieverting, then have a real destination instead of a random fallback.
	_dungeon.set_entrance(start)
	_dungeon.render_grid()  # builds the visible floor and walls from the logical grid
	var player := get_node_or_null("Player")
	if player != null and player.has_method("teleport_to"):
		player.teleport_to(start)
		# The scenarios extend towards +z, while the player looks towards -z by default — at the
		# wall behind them. Turn them towards the dungeon, body and yaw target alike.
		if player.has_method("set_start_yaw"):
			player.set_start_yaw(PI)


func _on_encounter_requested(rival: Node, initiated_by_rival: bool) -> void:
	if _pending_rival != null:
		return
	_pending_rival = rival
	# An encounter breaks any stealth the player had: fog mantel, torment veil, a costume.
	var pl := get_tree().get_first_node_in_group("player")
	if pl != null and pl.has_method("clear_hidden"):
		pl.clear_hidden()
	var rival_id: StringName = rival.species_id if "species_id" in rival else &"ravbak"
	# The rival's map state: its maximum DEN is a LEVEL DESIGN knob, and damage taken during
	# exploration — a fall — carries into the encounter. An empty dictionary means nothing was
	# tracked on the map, and the individual starts from its defaults.
	var rival_state := {}
	if "den" in rival and "max_den" in rival:
		rival_state = {"den": rival.den, "max_den": rival.max_den}
	print(
		(
			"[Exploration] Encounter with '%s' (rival-initiated=%s, map state=%s)."
			% [rival_id, initiated_by_rival, rival_state]
		)
	)
	TransitionManager.open_encounter(_player_duo(), [rival_id], {}, [rival_state])


func _on_encounter_finished(result: StringName) -> void:
	print("[Exploration] Encounter over: %s." % result)
	# FDE counter: every rival devitalised is exactly &"victory" — a defeat, a timeout or a
	# flight does not count.
	GameSession.register_encounter_end(result == &"victory")
	if result == &"victory" and is_instance_valid(_pending_rival):
		_pending_rival.queue_free()  # the rival is dissolved
	_pending_rival = null
	# If the whole duo is devitalised, this restores DEN to 1 each and emits party_wiped, which
	# runs _on_party_wiped to take the duo out of the dungeon.
	GameSession.resolve_party_wipe()


## The whole duo has been devitalised. [GameSession] has already restored DEN to 1 each;
## exploration has to take the duo out of the current dungeon.
func _on_party_wiped() -> void:
	print("[Exploration] Duo devitalised: leaving the dungeon.")
	## TODO: actually take the duo out of the dungeon — back to the world map, or to the
	## dungeon entrance — once inter-scene navigation exists.


func _on_turn_advanced(_turn: int) -> void:
	pass  # turn hook: PSY, IFP, and so on


# --------------------------------------------------------------------------
# Real-time narrow-bridge driver (the balance test)
# --------------------------------------------------------------------------


func _process(delta: float) -> void:
	_drive_bridge(delta)


func _drive_bridge(delta: float) -> void:
	var player := get_node_or_null("Player")
	if player == null:
		return
	# Detects an engaged bridge tile, meaning we have stepped onto a plank.
	if _active_bridge == null:
		for m in _dungeon.get_children():
			if m.has_method("is_engaged") and m.is_engaged():
				_begin_bridge_tile(m, player)
				break
		return
	# Lateral input, INVERTED so that it CORRECTS: leaning the right way restores balance.
	var input := -Input.get_axis("move_left", "move_right")
	var state: StringName = _active_bridge.advance(delta, input)
	var bal = _active_bridge.balance()
	# Advance along the tile (from -> from+dir); imbalance shows up as camera ROLL.
	var t := clampf(bal.progress, 0.0, 1.0)
	var from_w := _dungeon.tile_to_world(_bridge_from)
	var to_w := _dungeon.tile_to_world(_bridge_from + _bridge_dir)
	player.global_position = from_w.lerp(to_w, t)
	_set_camera_roll(player, bal.imbalance)
	_hud_show_balance(bal.imbalance)
	if state == &"complete":
		_advance_bridge_tile(player)
	elif state == &"fell":
		_fall_off_bridge(player)


## Starts an advance onto a bridge tile, along the direction being faced. When a crossing is
## already under way, the tile PICKS UP the current balance test — imbalance and lateral
## velocity both carried over — instead of starting a fresh one.
func _begin_bridge_tile(bridge, player) -> void:
	_active_bridge = bridge
	_bridge_dir = bridge.direction()
	_bridge_from = bridge.tile
	if _in_bridge and _bridge_balance != null:
		bridge.adopt_balance(_bridge_balance)
	else:
		_in_bridge = true
		_bridge_balance = bridge.balance()
	player.input_locked = true
	_hud_show_balance(_bridge_balance.imbalance)


## Tile crossed: move to the next one, carrying on if there is more bridge, otherwise finishing.
##
## The design doc: "turns here are not defined by player interaction, but by bridge length" —
## so every bridge tile crossed costs one turn, exactly like an ordinary step.
func _advance_bridge_tile(player) -> void:
	var dest: Vector3i = _bridge_from + _bridge_dir
	_bridge_balance = _active_bridge.balance()  # carried to the next tile
	_active_bridge = null
	# A bridge tile crossed IS a move, so it counts down disarray like any step. The deflection
	# itself makes no sense here — you get no choice of direction on a plank — and on a bridge
	# disarray shows up as command inertia instead. This holds for EVERY branch below: the tile
	# is crossed whether or not someone is standing on it.
	var aff = player.get("affliction")
	if aff != null:
		aff.consume_move()
	# Someone already occupies the destination. The mirror image of a rival coming towards us
	# ([method RivalBehavior.take_turn]): on a plank both fall, on solid floor it is ordinary
	# contact.
	var occupant := _dungeon.occupant_at(dest)
	if occupant != null:
		if _dungeon.is_narrow_bridge(dest):
			_on_bridge_collision(occupant, dest)
		else:
			_finish_bridge(player)
			player.teleport_to(dest)
			# Stepping off the bridge IS a move, so it costs a turn like any other step — unlike
			# contact on the spot, where the player does not move. The turn elapses BEFORE the
			# encounter, the same order as a plank collision, where the fall is what advances it.
			_dungeon.advance_turn()
			# The rival may have moved, or been dissolved, during that turn: no encounter with
			# someone who is no longer there.
			if is_instance_valid(occupant) and _dungeon.occupant_at(dest) == occupant:
				_dungeon.request_encounter(occupant, false)
		return
	player.teleport_to(dest)
	_dungeon.notify_entered(dest, player)  # engages the next tile if it is still bridge
	var still := false
	for m in _dungeon.mechanisms_at(dest):
		if m.has_method("is_engaged") and m.is_engaged():
			still = true
	if not still:
		_finish_bridge(player)  # landed on solid floor
	_dungeon.advance_turn()


## Falling off the bridge: the character drops to the FLOOR below, as deep as level design made
## it, and takes NORMAL fall damage, exactly like stepping into empty space.
func _fall_off_bridge(player) -> void:
	# You fall from whichever tile you are closest to: the one ahead if you are past halfway AND
	# there is genuinely empty space below it — otherwise you are already over solid floor.
	var from_tile := _bridge_from
	var ahead: Vector3i = _bridge_from + _bridge_dir
	if (
		_active_bridge != null
		and _active_bridge.balance().progress >= 0.5
		and _dungeon.fall_landing(ahead) != ahead
	):
		from_tile = ahead
	_finish_bridge(player)
	var landing := _dungeon.fall_landing(from_tile)
	if landing == from_tile:
		# Nothing below: the bridge spans no gap at all, which is incomplete level design. Catch
		# yourself on the plank rather than vanishing.
		## TODO(dungeon checker): the design doc requires a narrow bridge to ALWAYS span a floor,
		## with a way back up before the bridge (unless the fall devitalises). Nothing checks that
		## on a real dungeon — only the dev scenario is verified, by `geometry_check`. Revisit
		## when a dungeon validator exists; until then, this runtime guardrail.
		push_warning("[Exploration] Fall off the bridge at %s: no floor below." % from_tile)
		player.teleport_to(from_tile)
		return
	player.teleport_to(from_tile)
	# Watching rivals are told by `fall_to`, through `DungeonManager.notify_level_change`.
	await player.fall_to(landing, from_tile.y - landing.y)


## A rival steps onto the plank the player is on: both fall, land on the SAME tile, and the
## encounter starts there, per the design doc. The rival may be devitalised by the fall, in
## which case there is no encounter at all.
func _on_bridge_collision(rival, tile: Vector3i) -> void:
	var player := get_node_or_null("Player")
	if player == null or not is_instance_valid(rival):
		return
	var landing := _dungeon.fall_landing(tile)
	if landing == tile:
		return  # nothing empty under this plank: nobody falls
	var levels := tile.y - landing.y
	_finish_bridge(player)  # the crossing is cut short
	player.teleport_to(tile)
	# The player occupies no tile, so the rival can land exactly on theirs.
	var rival_alive: bool = rival.drop_to(landing, levels)
	await player.fall_to(landing, levels)
	if rival_alive and is_instance_valid(rival):
		_dungeon.request_encounter(rival, true)


func _finish_bridge(player) -> void:
	_active_bridge = null
	_in_bridge = false
	_bridge_balance = null
	player.input_locked = false
	_set_camera_roll(player, 0.0)
	_hud_hide_balance()


## The roll of losing your balance, applied to the PLAYER — whose pivot is at the origin, near
## the feet — and not to the camera rig, which would pivot at eye level.
func _set_camera_roll(player, imbalance: float) -> void:
	player.rotation.z = deg_to_rad(imbalance * BRIDGE_ROLL_DEG)


func _hud_show_balance(imbalance: float) -> void:
	var hud := get_node_or_null("HudExploration")
	if hud != null and hud.has_method("show_balance"):
		hud.show_balance(imbalance)


func _hud_hide_balance() -> void:
	var hud := get_node_or_null("HudExploration")
	if hud != null and hud.has_method("hide_balance"):
		hud.hide_balance()


## The playable duo from the session, with a demo fallback when the run is not initialised.
func _player_duo() -> Array:
	var ids: Array = []
	if GameSession.main_character != &"":
		ids.append(GameSession.main_character)
	if GameSession.teammate != &"":
		ids.append(GameSession.teammate)
	if ids.is_empty():
		# Demo fallback: a DUO, so the teammate shows up in the turn order while the run does not
		# set main_character/teammate. draka is the main character; kalilk is only a stand-in
		# teammate, picked because it has a sprite and so a visible turn-order portrait. The real
		# teammate is the duo's second personality, which has no species and no assets yet.
		ids = [&"draka", &"kalilk"]
	return ids
