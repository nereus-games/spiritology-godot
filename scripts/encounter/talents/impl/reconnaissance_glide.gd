## Reconnaissance Glide (ravbak).
##
## The ENCOUNTER half, handled here — "Examine (if used by this character) gets 10% more info on
## target" — through [method modify_examine_info]: the factor it returns multiplies the bonuses
## the bearer's Examine already carries (see `examine_yield.gd`), and the product is the
## `yield_factor` the IFP are scaled by, rounded up ([method GameSession.scale_amount]).
##
## The EXPLORATION half is NOT handled here and waits on the dungeon framework — "Falling doesn't
## deal any damage to player characters" belongs to the dungeon mechanisms.
extends "res://scripts/encounter/talents/talent_script.gd"

const EXAMINE_INFO_BONUS := 0.10  ## +10%, the design doc's figure, multiplies the factor so far.


func modify_examine_info(_manager, _target, base: float) -> float:
	return base * (1.0 + EXAMINE_INFO_BONUS)
