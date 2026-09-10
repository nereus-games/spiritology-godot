## Reconnaissance Glide (ravbak).
##
## The ENCOUNTER half, handled here — "Examine (if used by this character) gets 10% more info on
## target" — through [method modify_examine_info]. An Examine has no quantified magnitude, since
## its info gain is not built, so the effect stays a factor with nothing to multiply until that
## system exists: an honest stub, but the hook is wired.
##
## The EXPLORATION half is NOT handled here and waits on the dungeon framework — "Falling doesn't
## deal any damage to player characters" belongs to the dungeon mechanisms.
extends "res://scripts/encounter/talents/talent_script.gd"

const EXAMINE_INFO_BONUS := 0.10  ## +10%, the design doc's figure, applied to the base gain.


func modify_examine_info(_manager, _target, base: float) -> float:
	return base * (1.0 + EXAMINE_INFO_BONUS)
