## Tumult — Encounter · origine firulis · Fluid · coût medium · dégâts normal (10)
## Tags : change weakness, damage
##
## MÉCANIQUE (Notion) :
##   Each individual’s Weakness is changed at random (must be a different one).
##   Each individual has a X % chance of being dealt damage.
##   UI effects: UI elements are placed differently (one where another should be), until
##   encounter’s end, unless one of the player characters uses Meditate (then UI goes back to
##   normal).
##
## Exemple d'effet UNIQUE implémenté à la main (override + RNG + UI).
extends AbilityScript

## Probabilité de dégâts par individu (« X % » Notion — à équilibrer).
const DAMAGE_CHANCE := 0.5

func execute(ctx: EncounterContext) -> void:
	var everyone: Array = ctx.all_fighters if not ctx.all_fighters.is_empty() else ctx.targets
	for fighter in everyone:
		# Faiblesse changée au hasard (forcément différente — détail dans la rencontre).
		ctx.change_weakness(fighter)
		if ctx.rng.randf() < DAMAGE_CHANCE:
			ctx.deal_damage(fighter, ctx.ability.base_damage)
	# Perturbation d'UI persistante jusqu'à la fin de la rencontre (annulée par Meditate).
	ctx.request_ui(&"shuffle_ui", {"until": "encounter_end", "cancel_on": "meditate"})
