## Headless check on the narrow bridge's balance MODEL ([NarrowBridgeBalance]).
##
## The bridge's tuning cannot be judged by eye: thousands of crossings are simulated with virtual
## "players" of increasing skill, and the fall rate is checked to stay inside the intended band.
## That is what protects the tuning from a silent regression.
##
## The design contract verified here:
##   - do nothing            -> you fall (the inverted pendulum diverges);
##   - correct too little    -> you fall often (the gusts push you off the plank);
##   - correct normally      -> you get across most of the time;
##   - correct with anticipation -> you get across;
##   - PSY makes the test harder, and so does disarray.
##
## Run with: Godot --headless --path . res://scenes/dev/bridge_balance_check.tscn
## As a start scene rather than --script; see geometry_check.gd.
extends Node

const NarrowBridgeBalance := preload("res://scripts/exploration/narrow_bridge_balance.gd")

## The simulated time step (60 Hz) and the reference bridge length.
const DT := 1.0 / 60.0
const CELLS := 5
const RUNS := 1500

var _fails: Array[String] = []

## "Player" profiles: reaction latency (s), how far ahead velocity is anticipated (s), and a
## dead zone below which the player does not correct at all. `passive` touches nothing.
const PROFILES := {
	"passif": {"reaction": 999.0, "lookahead": 0.0, "deadzone": 0.0, "passive": true},
	"mou": {"reaction": 0.35, "lookahead": 0.0, "deadzone": 0.35, "passive": false},
	"normal": {"reaction": 0.25, "lookahead": 0.12, "deadzone": 0.08, "passive": false},
	"attentif": {"reaction": 0.18, "lookahead": 0.25, "deadzone": 0.05, "passive": false},
}


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  OK   %s" % label)
	else:
		print("  FAIL %s" % label)
		_fails.append(label)


func _ready() -> void:
	_run_all()


func _run_all() -> void:
	print("A %d-cell bridge, %d crossings per measurement.\n" % [CELLS, RUNS])

	print("[fall rate by player profile — PSY 0, no disarray]")
	var base := {}
	for name in PROFILES:
		base[name] = _fall_rate(name, 0, false)
		print("  %-9s %5.1f %%" % [name, base[name]])
	_check(base["passif"] > 95.0, "doing nothing makes you fall (%.1f %%)" % base["passif"])
	_check(base["mou"] > 45.0, "correcting too little makes you fall often (%.1f %%)" % base["mou"])
	_check(
		base["normal"] > 3.0 and base["normal"] < 30.0,
		"a normal player usually gets across, but never for granted (%.1f %%)" % base["normal"]
	)
	_check(base["attentif"] < 5.0, "anticipating is enough to cross (%.1f %%)" % base["attentif"])
	_check(
		base["mou"] > base["normal"] and base["normal"] > base["attentif"],
		"the fall rate decreases strictly with how well the player plays"
	)

	print("\n[effect of PSY — normal player, no disarray]")
	var psy_rates := []
	for psy in [0, 10, 20, 30, 40]:
		var r := _fall_rate("normal", psy, false)
		psy_rates.append(r)
		print("  PSY %-3d %5.1f %%" % [psy, r])
	_check(
		psy_rates[4] > psy_rates[0] + 10.0,
		"a high PSY clearly hardens the test (%.1f %% -> %.1f %%)" % [psy_rates[0], psy_rates[4]]
	)
	_check(
		psy_rates[4] < 85.0,
		"a high PSY does not make the bridge impassable (%.1f %%)" % psy_rates[4]
	)

	print(
		(
			"\n[effect of disarray — command inertia +%.0f %%]"
			% (NarrowBridgeBalance.DISARRAY_INERTIA * 100.0)
		)
	)
	for psy in [0, 20]:
		var clean := _fall_rate("normal", psy, false)
		var dis := _fall_rate("normal", psy, true)
		print("  PSY %-3d %5.1f %%  ->  %5.1f %% under disarray" % [psy, clean, dis])
		_check(
			dis > clean,
			"PSY %d: disarray makes the test harder (%.1f -> %.1f %%)" % [psy, clean, dis]
		)

	print("")
	if _fails.is_empty():
		print("ALL OK")
	else:
		print("FAILURES: %s" % [_fails])
	get_tree().quit(0 if _fails.is_empty() else 1)


## Fall rate, as a percentage, over [constant RUNS] complete crossings.
func _fall_rate(profile: String, psy: int, disarrayed: bool) -> float:
	var fell := 0
	for i in range(RUNS):
		if not _cross(profile, psy, disarrayed, i):
			fell += 1
	return 100.0 * float(fell) / float(RUNS)


## One complete crossing: [constant CELLS] cells chained on the SAME model, so imbalance and
## lateral velocity carry across the cell boundaries. Returns `true` when the simulated player
## reaches the other side.
func _cross(profile: String, psy: int, disarrayed: bool, seed_value: int) -> bool:
	var p: Dictionary = PROFILES[profile]
	var bal = NarrowBridgeBalance.new(seed_value)
	bal.configure(psy, 1, disarrayed)
	var input := 0.0
	var since := 0.0
	for _cell in range(CELLS):
		bal.restart_cell()
		while not bal.is_complete():
			if not p["passive"]:
				since += DT
				if since >= p["reaction"]:
					since = 0.0
					# The player aims for the centre from what they SEE (the roll) and, if they are
					# good, from how fast it is getting away.
					var seen: float = bal.imbalance + p["lookahead"] * bal.lateral_velocity
					input = 0.0 if absf(seen) < p["deadzone"] else (-1.0 if seen > 0.0 else 1.0)
			bal.tick(DT, input)
			if bal.is_fallen():
				return false
	return true
