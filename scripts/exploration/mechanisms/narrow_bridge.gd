## One narrow-bridge cell — a log over a drop — and its balance test.
##
## Per the design doc the character ADVANCES ON ITS OWN, and the player corrects in real time
## with lateral moves to stay upright. Every cell of the bridge carries this mechanism: stepping
## onto one engages a balance test that advances ONE cell along the direction being FACED, so a
## bridge works in both directions. The pure balance logic lives in [NarrowBridgeBalance]; the
## real-time driver — lateral input, camera roll, chaining cell to cell, falling — is in
## `exploration.gd`.
##
## No `class_name`: `extends` by path. References the GameSession autoload, for the PSY score.
extends "res://scripts/exploration/mechanisms/dungeon_mechanism.gd"

const NarrowBridgeBalance := preload("res://scripts/exploration/narrow_bridge_balance.gd")

var _balance
var _engaged := false
var _dir := Vector3i(0, 0, 1)


## A bridge is not an obstacle: you can step onto it, which engages the test.
func blocks_walk() -> bool:
	return false


func on_enter(who: Node) -> void:
	if _engaged:
		return
	if _dungeon != null and not _dungeon.is_player(who):
		return  # the balance test only concerns the player
	var disarrayed := false
	var aff = who.get("affliction")
	if aff != null:
		disarrayed = aff.has_disarray()
	engage(who.facing_delta(), disarrayed)


## Engages the balance test to advance ONE cell along `dir`.
func engage(dir: Vector3i, disarrayed: bool) -> void:
	_dir = dir if dir != Vector3i.ZERO else Vector3i(0, 0, 1)
	_balance = NarrowBridgeBalance.new()
	_balance.configure(GameSession.psy_score, 1, disarrayed)  # one cell
	_engaged = true


## Picks up the balance test ALREADY UNDER WAY, from a crossing started on the previous cell,
## rather than starting a fresh one: imbalance and lateral velocity carry across the cell
## boundary. Otherwise the momentum would be wiped every couple of seconds — the opposite of
## inertia.
func adopt_balance(running) -> void:
	if running == null:
		return
	_balance = running
	_balance.restart_cell()


## Advances the test one time step with the lateral input, in [-1, 1]. Returns &"balancing",
## &"fell" or &"complete".
func advance(delta: float, lateral_input: float) -> StringName:
	if not _engaged or _balance == null:
		return &"complete"
	_balance.tick(delta, lateral_input)
	if _balance.is_fallen():
		_engaged = false
		return &"fell"
	if _balance.is_complete():
		_engaged = false
		return &"complete"
	return &"balancing"


func is_engaged() -> bool:
	return _engaged


func direction() -> Vector3i:
	return _dir


## The balance model itself; the driver reads and writes imbalance through it to chain cells.
func balance():
	return _balance

# No generic marker: the planks are placed by the scenario, or by level design.
