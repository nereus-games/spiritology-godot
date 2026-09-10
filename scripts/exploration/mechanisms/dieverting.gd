## Dieverting (French name: "cubimprévu").
##
## From the design doc ("Mechanisms / Dieverting"). An impatient die that goes off the moment
## it meets the player. If the player holds something able to destroy it — a spade or a rune
## stone — they get the CHOICE of destroying it or submitting; otherwise they submit at once.
## The roll gives one of 6 outcomes. Treated as a mechanism rather than an object, so it never
## goes into the inventory.
##
## The destroy/submit choice is offered by the HUD's contextual action menu, like unlocking a
## gateway: until the player picks one, the die stays PENDING on its cell and offers both
## actions again on every visit.
##
## It is a REAL d6 (opposite faces sum to 7): each of the design doc's 6 outcomes is a face,
## the cube genuinely tumbles and stops on the one it rolled, and the result is announced
## through the HUD's message banner ([method DungeonManager.post_message]).
##
## Two points the design doc leaves open, settled here:
##  - a die that has rolled, or been destroyed, is consumed: it never rearms, neither during
##    the visit nor between two of them;
##  - the X / Y / Z magnitudes (objects lost, ETH, DEN) are exported placeholders.
##
## No `class_name`: `extends` by path. References the GameSession autoload.
extends "res://scripts/exploration/mechanisms/dungeon_mechanism.gd"

const ExplorationAction := preload("res://scripts/exploration/exploration_action.gd")
const ChestScript := preload("res://scripts/exploration/mechanisms/chest.gd")
const RIVAL_SCENE := preload("res://scenes/exploration/rival/rival.tscn")

## The die's 6 outcomes, from the design doc.
enum Outcome {
	TELEPORT_ENTRANCE_LOSE_OBJECTS,  ## to the entrance, losing objects (dropped in a chest)
	TELEPORT_ENTRANCE_LOSE_ETH,  ## to the entrance, each character losing ETH
	SPAWN_RIVALS,  ## up to 3 groups of rivals appear
	TELEPORT_EXIT_LOSE_OBJECTS_DEN,  ## to an exit, losing objects, each character losing DEN
	DESTROY_OBJECTS,  ## destroys up to 3 random objects
	ADD_OBJECTS,  ## adds up to 3 random objects
}

## Objects able to destroy a dieverting.
const DESTROYERS: Array[StringName] = [&"spade", &"rune_stone"]

## Objects the ADD_OBJECTS outcome can hand out. Placeholder.
@export var add_pool: Array[StringName] = [&"rune_stone", &"tea_drop", &"smoke_bomb", &"spade"]

# Placeholder magnitudes — the design doc leaves X / Y / Z to be defined.
@export var objects_lost := 2
@export var eth_lost_each := 10
@export var den_lost_each := 15
@export var max_objects_delta := 3

## The SPAWN_RIVALS outcome: up to 3 GROUPS of rivals (one silhouette on the map is one group)
## within `rival_spawn_radius` cells of the player.
## ## TODO: the design doc says "specifics TBD" — the count, the distance and above all the
## species will have to come from level design (DungeonConfig.possible_species) once dungeons
## are authored. The pool below is a test placeholder.
@export var rival_spawn_max := 3
@export var rival_spawn_radius := 4
@export var rival_pool: Array[StringName] = [&"ravbak", &"kalilk"]

# --- The die (visuals) ---

## Edge length of the cube, in metres.
const DIE_SIZE := 0.45
## A pip's side, how far it stands proud of the face, and the gap between two pips.
const PIP_SIZE := 0.075
const PIP_DEPTH := 0.012
const PIP_SPACING := DIE_SIZE * 0.26

## Each face's LOCAL normal, with opposite faces summing to 7, like a real die.
const FACE_NORMALS := {
	1: Vector3.UP,
	6: Vector3.DOWN,
	2: Vector3.BACK,
	5: Vector3.FORWARD,
	3: Vector3.RIGHT,
	4: Vector3.LEFT,
}

## Pip layout of a face, in units of [constant PIP_SPACING].
const PIP_LAYOUTS := {
	1: [Vector2(0, 0)],
	2: [Vector2(-1, -1), Vector2(1, 1)],
	3: [Vector2(-1, -1), Vector2(0, 0), Vector2(1, 1)],
	4: [Vector2(-1, -1), Vector2(-1, 1), Vector2(1, -1), Vector2(1, 1)],
	5: [Vector2(-1, -1), Vector2(-1, 1), Vector2(0, 0), Vector2(1, -1), Vector2(1, 1)],
	6:
	[Vector2(-1, -1), Vector2(-1, 0), Vector2(-1, 1), Vector2(1, -1), Vector2(1, 0), Vector2(1, 1)],
}

## Tumble duration in seconds. 0 means no animation at all, for the headless checks.
@export var roll_duration := 0.9
## How long the die stays readable in mid-air before dropping back onto its cell.
@export var roll_hold := 0.7

## How far in front of the player, and how high, the die tumbles. The player stands on the SAME
## cell as the die, so a 45 cm cube left on the floor would sit below the camera (eyes at
## [constant DungeonManager.EYE_HEIGHT]) and be invisible. It therefore jumps into view, a
## little past the neighbouring cell — any closer and it fills the screen.
## ## TODO: in a dead end the airborne die clips into the wall opposite. Cosmetic; revisit with
## the real visuals.
const AIR_DISTANCE := 1.45
const AIR_HEIGHT := 0.45  # cube centre near eye height, so the die sits right on the axis

## Message key per outcome, shown by the HUD through
## [signal DungeonManager.message_posted].
const MESSAGE_KEYS := {
	Outcome.TELEPORT_ENTRANCE_LOSE_OBJECTS: "UI_DIEVERTING_ENTRANCE_OBJECTS",
	Outcome.TELEPORT_ENTRANCE_LOSE_ETH: "UI_DIEVERTING_ENTRANCE_ETH",
	Outcome.SPAWN_RIVALS: "UI_DIEVERTING_RIVALS",
	Outcome.TELEPORT_EXIT_LOSE_OBJECTS_DEN: "UI_DIEVERTING_EXIT_OBJECTS_DEN",
	Outcome.DESTROY_OBJECTS: "UI_DIEVERTING_DESTROY_OBJECTS",
	Outcome.ADD_OBJECTS: "UI_DIEVERTING_ADD_OBJECTS",
}

var _active := true
## The die met the player, who can destroy it: the choice is pending on the cell.
var _pending := false

# State of the tumble in progress, read by [method _roll_step] and driven by a tween.
var _roll_axis := Vector3.UP
var _roll_turns := 2.0
var _roll_final := Quaternion.IDENTITY


func is_active() -> bool:
	return _active


## A die that has rolled, or been destroyed, is spent.
func is_spent() -> bool:
	return not _active


func is_pending() -> bool:
	return _pending


## Whether the player can destroy this dieverting, meaning they hold a spade or a rune stone.
func is_destroyable_by(who: Node) -> bool:
	if _dungeon != null and not _dungeon.is_player(who):
		return false
	for obj in DESTROYERS:
		if GameSession.has_object(obj):
			return true
	return false


## Meeting the die: if the player cannot destroy it, it goes off at once — it is "impatient".
## If they can, the choice goes through the action menu.
func on_enter(who: Node) -> void:
	if not _active:
		return
	if _dungeon != null and not _dungeon.is_player(who):
		return
	if is_destroyable_by(who):
		_pending = true
		return
	submit(who)


## What is offered while the choice is pending: destroy it, at the cost of an object, or
## submit.
func on_tile_actions(who: Node) -> Array:
	if not _active or not _pending:
		return []
	var actions: Array = []
	if is_destroyable_by(who):
		actions.append(
			ExplorationAction.new(
				&"destroy_dieverting",
				"UI_ACTION_DESTROY_DIEVERTING",
				Callable(self, "destroy").bind(who)
			)
		)
	actions.append(
		ExplorationAction.new(
			&"submit_dieverting", "UI_ACTION_SUBMIT_DIEVERTING", Callable(self, "submit").bind(who)
		)
	)
	return actions


## Destroys the dieverting, consuming one destroyer object — the spade first. Returns true when
## it was destroyed.
func destroy(_who: Node) -> bool:
	if not _active:
		return false
	for obj in DESTROYERS:
		if GameSession.has_object(obj):
			GameSession.consume_object(obj)
			_deactivate()
			_post_message("UI_DIEVERTING_DESTROYED", [])
			return true
	return false


## Submits to the die: rolls it (or takes `forced`, for tests), tumbles it in front of the
## player, announces the result, then applies the outcome. AWAIT it if you need the effects to
## have landed — the outcome is only applied once the die has come down. `roll_duration = 0`
## short-circuits the animation. Returns the outcome rolled.
func submit(who: Node, forced: int = -1) -> int:
	if not _active:
		return -1
	var outcome := forced if forced >= 0 else randi() % Outcome.size()
	# Disarmed BEFORE the roll: the die has played, even if the animation is still running. The
	# outcome itself may drop a chest on the cell, spawn rivals or teleport the player, so it is
	# only applied once the die has come down.
	_active = false
	_pending = false
	var locked: bool = "input_locked" in who
	if locked:
		who.input_locked = true  # you do not walk off in the middle of a roll
	await _play_roll(outcome + 1, who)  # faces 1..6 are the 6 outcomes, in the design doc's order
	_post_message("UI_DIEVERTING_ROLL", [outcome + 1, tr(MESSAGE_KEYS[outcome])])
	await _settle_back()
	_mark_rolled()
	if locked and is_instance_valid(who):
		who.input_locked = false
	_apply(outcome, who)
	return outcome


func _apply(outcome: int, who: Node) -> void:
	match outcome:
		Outcome.TELEPORT_ENTRANCE_LOSE_OBJECTS:
			_teleport_to_entrance(who)
			_drop_chest(_lose_objects(objects_lost))
		Outcome.TELEPORT_ENTRANCE_LOSE_ETH:
			_teleport_to_entrance(who)
			_drain_party_eth(eth_lost_each)
		Outcome.SPAWN_RIVALS:
			_spawn_rival_groups(who)
		Outcome.TELEPORT_EXIT_LOSE_OBJECTS_DEN:
			_teleport_to_exit(who)
			_drop_chest(_lose_objects(objects_lost))
			_damage_party_den(den_lost_each)
		Outcome.DESTROY_OBJECTS:
			_lose_objects(randi_range(1, max_objects_delta))  # "up to 3"
		Outcome.ADD_OBJECTS:
			_add_objects(max_objects_delta)


## Sends the player back to the dungeon's ENTRANCE. With no entrance declared — a dev scenario,
## say — it falls back to a random cell, like a teleport trap.
func _teleport_to_entrance(who: Node) -> void:
	if _dungeon == null:
		return
	if _dungeon.has_entrance():
		_dungeon.teleport_actor_to(who, _dungeon.entrance_cell())
	else:
		_dungeon.teleport_actor(who)


## Sends the player to an EXIT, drawn at random when there is more than one, per the design
## doc. The entrance counts as one (see [method DungeonManager.set_entrance]).
func _teleport_to_exit(who: Node) -> void:
	if _dungeon == null:
		return
	if _dungeon.has_exit():
		_dungeon.teleport_actor_to(who, _dungeon.random_exit())
	else:
		_dungeon.teleport_actor(who)


## Removes `count` random objects from the inventory and returns what was lost, for the chest.
## An object held in several copies can come up more than once.
func _lose_objects(count: int) -> Array[StringName]:
	var lost: Array[StringName] = []
	for i in range(count):
		var owned: Array = GameSession.inventory.keys()
		if owned.is_empty():
			break
		var object_id: StringName = owned[randi() % owned.size()]
		GameSession.remove_object(object_id, 1)
		lost.append(object_id)
	return lost


## Drops the lost objects into a chest placed WHERE THE DIEVERTING WAS, per the design doc. The
## die is inert by then, so both mechanisms share the cell.
func _drop_chest(lost: Array[StringName]) -> void:
	if lost.is_empty() or _dungeon == null:
		return
	var chest = ChestScript.new()
	chest.fixed_loot = lost
	chest.position = _dungeon.cell_to_world(cell)
	_dungeon.add_child(chest)


func _add_objects(max_count: int) -> void:
	var n := randi_range(1, max_count)
	for i in range(n):
		if not add_pool.is_empty():
			GameSession.add_object(add_pool[randi() % add_pool.size()], 1)


## Spawns 1 to [member rival_spawn_max] groups of rivals near the player.
func _spawn_rival_groups(who: Node) -> void:
	if _dungeon == null or rival_pool.is_empty():
		return
	var origin: Vector3i = who.cell if "cell" in who else cell
	var spots: Array[Vector3i] = _dungeon.free_cells_near(origin, rival_spawn_radius)
	var n: int = mini(randi_range(1, rival_spawn_max), spots.size())
	for i in range(n):
		var rival = RIVAL_SCENE.instantiate()
		rival.species_id = rival_pool[randi() % rival_pool.size()]
		rival.position = _dungeon.cell_to_world(spots[i])
		_dungeon.add_child(rival)


func _drain_party_eth(amount: int) -> void:
	GameSession.spend_eth(GameSession.PartySlot.MAIN, amount)
	GameSession.spend_eth(GameSession.PartySlot.TEAMMATE, amount)


func _damage_party_den(amount: int) -> void:
	GameSession.apply_den_damage(GameSession.PartySlot.MAIN, amount)
	GameSession.apply_den_damage(GameSession.PartySlot.TEAMMATE, amount)
	GameSession.resolve_party_wipe()


func _deactivate() -> void:
	_active = false
	_pending = false
	_mark_spent()


## A consumed die, rolled or destroyed, does not come back on the next visit.
func reset_between_visits() -> void:
	pass


## Posts a feedback message for the player, shown by the HUD. `args` feeds the format string.
func _post_message(key: String, args: Array) -> void:
	if _dungeon == null:
		return
	var text := tr(key)
	if not args.is_empty():
		text = text % args
	_dungeon.post_message(text)


# --------------------------------------------------------------------------
# The die: visuals and rolling
# --------------------------------------------------------------------------


func _spawn_visual() -> void:
	var mesh := _add_marker(Color(0.9, 0.35, 0.1), DIE_SIZE, DIE_SIZE)  # orange cube
	# The die lights itself: the face that has to be READ is the one turned towards the player,
	# and so often the one in the dungeon's shadow.
	var mat := mesh.material_override as StandardMaterial3D
	if mat != null:
		mat.emission_enabled = true
		mat.emission = Color(0.9, 0.35, 0.1)
		mat.emission_energy_multiplier = 0.45
	_add_pips()


## Pips for all 6 faces, laid just proud of each face of the cube. Children of the marker, so
## they tumble with it.
func _add_pips() -> void:
	if _marker == null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.09, 0.07)
	var half := DIE_SIZE * 0.5
	for value in FACE_NORMALS:
		var n: Vector3 = FACE_NORMALS[value]
		# Two axes in the face's PLANE — any two will do, a die has no up.
		var u := n.cross(Vector3.UP)
		if u.length_squared() < 0.01:
			u = n.cross(Vector3.BACK)
		u = u.normalized()
		var w := n.cross(u).normalized()
		# A flat disc, thin along the face's axis, rather than a cube sticking out.
		var size: Vector3 = (u.abs() + w.abs()) * PIP_SIZE + n.abs() * PIP_DEPTH
		for offset in PIP_LAYOUTS[value]:
			var pip := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = size
			pip.mesh = box
			pip.material_override = mat
			pip.position = (
				n * (half + PIP_DEPTH * 0.5)
				+ u * (offset.x * PIP_SPACING)
				+ w * (offset.y * PIP_SPACING)
			)
			_marker.add_child(pip)


## The tumble: the die jumps into the player's view, spins as it slows, and stops on `face`,
## turned towards them. Returns once the die is still, so await it.
func _play_roll(face: int, who: Node) -> void:
	if roll_duration <= 0.0 or _marker == null:
		if _marker != null:
			_marker.basis = _basis_for_face(face, -_facing_of(who))
		return
	var facing := _facing_of(who)
	var air: Vector3 = _rest_position() + facing * AIR_DISTANCE + Vector3(0.0, AIR_HEIGHT, 0.0)
	# An arbitrary tumble axis — a thrown die does not spin around a chosen one — and 2 to 3
	# turns: enough to read the motion, not enough to blur the final face.
	_roll_axis = (
		Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
	)
	_roll_turns = randf_range(2.0, 3.0)
	_roll_final = Quaternion(_basis_for_face(face, -facing).orthonormalized())
	var tween := create_tween()
	tween.tween_method(_roll_step, 0.0, 1.0, roll_duration)
	(
		tween
		. parallel()
		. tween_property(_marker, "position", air, roll_duration * 0.45)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	await tween.finished


## One tumble step: a rotation that slows down, blended into the final orientation at the end.
func _roll_step(t: float) -> void:
	if not is_instance_valid(_marker):
		return
	var eased := 1.0 - pow(1.0 - t, 3.0)
	var tumble := Quaternion(_roll_axis, _roll_turns * TAU * eased)
	var blend := clampf((t - 0.6) / 0.4, 0.0, 1.0)
	_marker.basis = Basis(tumble.slerp(_roll_final, blend))


## The die stays readable in mid-air long enough to read the message, then drops back onto its
## cell.
func _settle_back() -> void:
	if _marker == null or roll_duration <= 0.0:
		return
	var tween := create_tween()
	tween.tween_interval(roll_hold)
	(
		tween
		. tween_property(_marker, "position", _rest_position(), 0.3)
		. set_trans(Tween.TRANS_BOUNCE)
		. set_ease(Tween.EASE_OUT)
	)
	await tween.finished


## The marker's rest position: resting at the centre of its cell (see `_add_marker_box`).
func _rest_position() -> Vector3:
	return Vector3(0.0, DIE_SIZE * 0.5, 0.0)


## The orientation that brings face `value` onto the LOCAL direction `toward`. Roll around that
## axis is a random quarter turn — so two throws never look alike — plus a slight skew: a die
## sitting askew, not a diamond balanced on its point.
func _basis_for_face(value: int, toward: Vector3) -> Basis:
	var n: Vector3 = FACE_NORMALS[value]
	var axis := toward.normalized()
	var roll := (randi() % 4) * PI * 0.5 + randf_range(-0.22, 0.22)
	return Basis(Quaternion(axis, roll) * Quaternion(n, axis))


## The "in front of the player" direction, in the mechanism's LOCAL frame.
func _facing_of(who: Node) -> Vector3:
	var dir := Vector3.BACK
	if who != null and who.has_method("facing_delta"):
		var fd: Vector3i = who.facing_delta()
		if fd != Vector3i.ZERO:
			dir = Vector3(fd.x, 0.0, fd.z).normalized()
	return (global_transform.basis.inverse() * dir).normalized()


## A rolled die is no longer actionable, so it GREYS OUT like any spent mechanism
## ([constant SPENT_COLOR]) instead of keeping the bright hue of an active one. It does keep its
## shape — no [method _mark_spent], which would flatten the cube — so the rolled face stays
## turned towards the player: the one lasting trace of what happened on this cell.
func _mark_rolled() -> void:
	if _marker == null:
		return
	_grey_marker()
	# The pips are nearly black: legible on bright orange, not at all on dark grey. Lighten them
	# so the face stays readable once the die has gone dull.
	var pip_mat := StandardMaterial3D.new()
	pip_mat.albedo_color = Color(0.86, 0.86, 0.88)
	for pip in _marker.get_children():
		if pip is MeshInstance3D:
			pip.material_override = pip_mat
