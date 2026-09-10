## A dungeon trap: disarray, teleport or poison.
##
## From the design doc ("Mechanisms / Traps"). A trap springs when an actor — player OR rival —
## enters its tile, as long as it is armed. Once sprung it does not disappear: it stays VISIBLE
## but disarmed. It can be revealed without being sprung (the future `reveal_traps` talent).
## Effects STACK through [AfflictionState]. Two versions exist, depending on whether it rearms
## between dungeon visits ([member reactivates]).
##
## No `class_name` (see dungeon_mechanism.gd): `extends` by path.
extends "res://scripts/exploration/mechanisms/dungeon_mechanism.gd"

## The kind of trap. Each kind has two versions, rearming or not, carried by
## [member reactivates] rather than by separate enum values.
enum Kind { DISARRAY, TELEPORT, POISON }

@export var kind: Kind = Kind.POISON

## The rearming version: the trap goes live again on every new visit to the dungeon.
@export var reactivates := false

## Whether the player can see its kind. A revealed trap is not thereby disarmed — the design
## doc: "When revealed (but not activated), a trap also reveals its type".
@export var revealed := false

# --- Placeholder magnitudes; the design doc leaves X / Y to be defined ---

## Poison: DEN taken per turn, and how many turns ("loses X DEN for each of Y turns").
##
## ## TODO: X and Y are still letters in the design doc. The values below are placeholders that
## have never been balanced — weigh them against rival DEN
## ([constant GameSession.RIVAL_DEN_EARLY] and friends) and against fall damage
## ([method DungeonManager.fall_damage], which the doc now gives real numbers for), so that
## poison costs the right amount next to the other sources of exploration damage.
@export var poison_per_turn := 5
@export var poison_turns := 3

## Disarray: bounds on how many moves are affected. The design doc says "3-5 movements".
@export var disarray_min := 3
@export var disarray_max := 5

## Armed means not yet sprung since the last reset.
var _active := true


func on_enter(who: Node) -> void:
	if not _active:
		return
	_trigger(who)
	_active = false  # disarmed once sprung, but still visible, greyed out
	revealed = true  # the player has seen the trap, and its kind
	_mark_spent()  # visual feedback: spent, since it fires once per visit
	# A trap that springs breaks invisibility (the fog mantel rule).
	if who.has_method("clear_invisibility"):
		who.clear_invisibility()


## A trap only shows on the map once it is KNOWN — revealed by a talent or an ability, or found
## out by springing it. While hidden the map says nothing about it, per the design doc's "User
## Interface".
func shows_on_map() -> bool:
	return revealed


## Reveals the trap's kind WITHOUT springing it (the future `reveal_traps` talent).
func reveal() -> void:
	revealed = true


## True while the trap has not been sprung since the last visit.
func is_active() -> bool:
	return _active


func is_spent() -> bool:
	return not _active


func reset_between_visits() -> void:
	if reactivates:
		_active = true
		revealed = false
		_respawn_marker()  # back to the armed look


func _trigger(who: Node) -> void:
	match kind:
		Kind.POISON:
			var aff = _affliction_of(who)
			if aff != null:
				aff.add_poison(poison_turns, poison_per_turn)
		Kind.DISARRAY:
			var aff = _affliction_of(who)
			if aff != null:
				aff.add_disarray(randi_range(disarray_min, disarray_max))
		Kind.TELEPORT:
			if _dungeon != null:
				_dungeon.teleport_actor(who)


## The actor's AfflictionState, or null when it has none. Duck typing: player and rival both
## expose an `affliction` property.
func _affliction_of(who: Node):
	return who.get("affliction")


func _spawn_visual() -> void:
	var color := Color(0.6, 0.2, 0.8)  # POISON: purple
	match kind:
		Kind.TELEPORT:
			color = Color(0.2, 0.5, 0.9)  # blue
		Kind.DISARRAY:
			color = Color(0.9, 0.5, 0.15)  # orange
	_add_marker(color, 0.22, 0.85)  # a slightly raised plate
	# An ARMED trap glows, to tell it apart from a spent one, which is grey and matte.
	var mat := _marker.material_override as StandardMaterial3D
	if mat != null:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 0.6
