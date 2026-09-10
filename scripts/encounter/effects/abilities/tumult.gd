## Tumult — Encounter · from firulis · Fluid · cost medium · damage normal (10)
## Tags: change weakness, damage
##
## MECHANIC (from the design doc):
##   Each individual’s Weakness is changed at random (must be a different one).
##   Each individual has a X % chance of being dealt damage.
##   UI effects: UI elements are placed differently (one where another should be), until
##   encounter’s end, unless one of the player characters uses Meditate (then UI goes back to
##   normal).
##
## An example of a ONE-OFF effect written by hand: an override plus RNG plus a UI request.
extends AbilityScript

## Damage chance per individual — the design doc's "X %", still to be balanced.
const DAMAGE_CHANCE := 0.5


func execute(ctx: EncounterContext) -> void:
	var everyone: Array = ctx.all_fighters if not ctx.all_fighters.is_empty() else ctx.targets
	for fighter in everyone:
		# Weakness changed at random; it is necessarily a different one, handled in the
		# encounter.
		ctx.change_weakness(fighter)
		if ctx.rng.randf() < DAMAGE_CHANCE:
			ctx.deal_damage(fighter, ctx.ability.base_damage)
	# A UI disturbance lasting until the end of the encounter, cleared by Meditate.
	ctx.request_ui(&"shuffle_ui", {"until": "encounter_end", "cancel_on": "meditate"})
