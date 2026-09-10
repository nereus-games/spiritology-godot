## Reuse (jézal) — "Single-use Encounter Abilities have a 50 % chance of being reusable
## after each use within the same encounter."
##
## Every time the bearer spends a single-use ability, there is a 50% chance of it becoming
## available again for this encounter. The manager calls [method wants_reuse] right after marking
## the ability spent, and un-spends it when this returns true.
extends "res://scripts/encounter/talents/talent_script.gd"

## Not really a placeholder: the design doc does say "50 %", so this is the real value. It is
## still pulled out as a constant, like the other magnitudes, in case feel says otherwise.
const REUSE_CHANCE := 0.5


func wants_reuse(manager, user, ability) -> bool:
	if user != owner or ability == null or not ability.single_use:
		return false
	return manager.rng.randf() < REUSE_CHANCE
