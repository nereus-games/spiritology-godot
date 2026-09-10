## The balance model of a narrow bridge: a real-time balance test.
##
## From the design doc ("Mechanisms / Narrow Bridges"). Once on a bridge the character advances
## BY ITSELF, and the player has to correct in real time with lateral moves to stay upright.
## Imbalance scales with the PSY score, and under the disarray trap lateral inertia rises, which
## makes correcting less responsive.
##
## Three ways to fall, all of them intended:
##   - do nothing: the inverted pendulum diverges on its own;
##   - correct TOO LITTLE or TOO LATE: an uncountered gust pushes you off the plank;
##   - correct TOO MUCH: human latency plus command inertia turn overcorrection into a
##     diverging oscillation.
##
## The test is CONTINUOUS across the whole crossing: both `imbalance` and `lateral_velocity`
## carry from tile to tile (see [method restart_tile]) — that is the character's momentum. Only
## `progress` goes back to 0 on each tile.
##
## This script is PURE LOGIC, with no input and no rendering, driven frame by frame through
## [method tick]; the real-time driver (lateral input, forward animation, camera) hooks onto it
## in the engine. Kept separate so it can be tested headless.
##
## No `class_name` (the CLI class-cache trap): referenced by `preload`.
extends RefCounted

## Fall threshold: |imbalance| at or above this and the character goes over.
const FALL_THRESHOLD := 1.0

## BASE inertia of the lateral command: the time constant, in seconds, the player's input takes
## to build up AND to fall away. This is what the design doc's "X% more inertia" is a percentage
## of — without it, "+X%" would have nothing to add to.
const COMMAND_INERTIA := 0.10

## Inertia ADDED by the disarray trap, as a fraction of [constant COMMAND_INERTIA]. The design
## doc: "adding X% more inertia to lateral movements".
##
## Set to +25%: measured over 1500 crossings, that takes a normal player from 12.5% to 16.3%
## falls at PSY 0, and from 27.7% to 32.9% at PSY 20 — about a third more risk, noticeable
## without making the bridge impassable once stacked on a high PSY.
const DISARRAY_INERTIA := 0.25

## How long a gust takes to build, in seconds. Past that it is a real push, not noise.
const GUST_SMOOTH := 0.35
## How long a gust lives before the next one is rolled, in seconds.
const GUST_MIN_PERIOD := 0.5
const GUST_MAX_PERIOD := 1.4

## Current imbalance, unbounded in principle but bounded in practice by falling. Negative leans
## one way, positive the other.
var imbalance := 0.0
## Current lateral velocity, integrated into `imbalance`. CARRIED from tile to tile.
var lateral_velocity := 0.0
## Progress along the current tile, 0 to 1. The character advances on its own.
var progress := 0.0

# --- Parameters, tuned by sweep; see the target values in the comments ---
## Inverted-pendulum instability: the further you lean, the faster you go over. This is what
## FORCES you to keep correcting — with no input, imbalance diverges and you fall.
var instability := 1.2
## Base gust amplitude, independent of PSY. Deliberately the same order as
## [member input_strength]: an uncountered gust knocks you off, but stays counterable.
var base_perturbation := 0.9
## Extra amplitude per point of PSY, so imbalance scales with PSY. Kept small: any more and the
## gust outruns the correction, making the bridge impassable at high PSY.
var perturbation_per_psy := 0.008
## How effective lateral correction (A/D) is: it acts on velocity to counter the fall.
var input_strength := 1.2
## Progress per second along the tile, derived from the length in [method configure].
var forward_speed := 0.5
## How long one bridge tile takes, in seconds. The character advances on its own, carefully.
var seconds_per_tile := 2.0
## Proportional friction on lateral velocity, per second.
var friction := 0.8
## Inertia added by disarray, as a fraction of [constant COMMAND_INERTIA]. Above 0 the command
## is slower to build up AND to fall away, per the design doc.
var disarray_inertia := 0.0

var _amplitude := 0.9
## The current gust and its target; the current one reaches the target in
## [constant GUST_SMOOTH].
var _gust := 0.0
var _gust_target := 0.0
var _gust_timer := 0.0
## The lateral command ACTUALLY applied: it follows the player's input with command inertia.
var _applied_input := 0.0
var _fallen := false
var _rng := RandomNumberGenerator.new()


## `seed_value >= 0` makes the perturbations deterministic, for tests.
func _init(seed_value := -1) -> void:
	if seed_value >= 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()
	_gust_timer = _rng.randf_range(GUST_MIN_PERIOD, GUST_MAX_PERIOD)


## Configures the test from the PSY score, the length of a tile (always 1: the test is
## continuous, and each tile is one segment) and whether disarray is active.
func configure(psy_score: int, length: int = 1, disarrayed: bool = false) -> void:
	_amplitude = base_perturbation + maxi(psy_score, 0) * perturbation_per_psy
	forward_speed = 1.0 / (maxf(float(length), 1.0) * seconds_per_tile)
	disarray_inertia = DISARRAY_INERTIA if disarrayed else 0.0


## Tile crossed: on to the next one WITHOUT flattening the balance. Imbalance, lateral velocity,
## the gust in progress and the command already committed all carry over — otherwise every tile
## boundary would wipe the momentum.
func restart_tile() -> void:
	progress = 0.0


## Advances one time step. `lateral_input` in [-1, 1] is the player's lateral correction.
func tick(delta: float, lateral_input: float) -> void:
	if _fallen or is_complete():
		return
	# A CORRELATED gust: it settles in, lasts about a second, then changes. Unlike white noise,
	# which cancels itself out when integrated, it genuinely pushes — and that is what punishes
	# under-correction.
	_gust_timer -= delta
	if _gust_timer <= 0.0:
		_gust_target = _rng.randf_range(-1.0, 1.0) * _amplitude
		_gust_timer = _rng.randf_range(GUST_MIN_PERIOD, GUST_MAX_PERIOD)
	_gust = lerpf(_gust, _gust_target, minf(1.0, delta / GUST_SMOOTH))
	# Command inertia: input takes time to build up AND to fall away. Disarray lengthens that
	# time constant, so the correction arrives late, and therefore overshoots.
	var tau := COMMAND_INERTIA * (1.0 + disarray_inertia)
	_applied_input = lerpf(_applied_input, clampf(lateral_input, -1.0, 1.0), minf(1.0, delta / tau))
	# Inverted pendulum: the further you lean, the faster you go over. Unstable by design.
	lateral_velocity += imbalance * instability * delta
	lateral_velocity += _gust * delta
	lateral_velocity += _applied_input * input_strength * delta
	# Gentle proportional friction: it damps without killing small velocities, which the
	# instability needs in order to diverge at all.
	lateral_velocity *= maxf(0.0, 1.0 - friction * delta)
	imbalance += lateral_velocity * delta
	# The automatic advance, slightly uneven — you are balancing on something narrow.
	progress += forward_speed * delta * _rng.randf_range(0.75, 1.25)
	if absf(imbalance) >= FALL_THRESHOLD:
		_fallen = true


func is_fallen() -> bool:
	return _fallen


func is_complete() -> bool:
	return progress >= 1.0 and not _fallen


## Under way: engaged, neither fallen nor arrived.
func is_active() -> bool:
	return not _fallen and not is_complete()
