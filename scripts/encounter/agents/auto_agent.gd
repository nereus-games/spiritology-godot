## Plays an individual automatically — every rival, and players in headless runs.
##
## SCAFFOLDING, not a design from the doc: the first usable offensive ability, else the
## first usable one at all, aimed at the first legal target. It never plays an ability that
## takes its user out of the encounter: picking the first damaging ability, ravbak would open
## every encounter with Opening up Closing and be gone by the second turn.
##
## Targeting goes through the manager's shared rule
## ([method EncounterManager.candidate_targets]), the same one the player's menu uses, so the two
## cannot drift apart.
class_name AutoAgent
extends EncounterAgent


func decide(individual: EncounterIndividual, manager: EncounterManager) -> EncounterAction:
	var weighted := _weighted_action(individual, manager)
	if weighted != null:
		return weighted
	var ability := _choose_ability(individual, manager)
	if ability == null:
		# Nothing playable left — all spent, or all too expensive. Meditate costs nothing,
		# needs no target, and the doc grants it to rivals too: better to rebuild ETH than
		# to waste the turn. Talk and Use/Give Object are open to them as well, but the AI
		# does not play them — Talk needs the dialogue system, and rivals carry no objects.
		return EncounterAction.of_kind(EncounterAction.Kind.MEDITATE, [individual])
	var targets := manager.candidate_targets(individual, ability)
	return EncounterAction.use_ability(ability, [targets[0]] if not targets.is_empty() else [])


func _choose_ability(individual: EncounterIndividual, manager: EncounterManager) -> AbilityData:
	var fallback: AbilityData = null
	for a in manager.usable_abilities(individual):
		if EffectCatalog.script_for(a).takes_user_away():
			continue
		if fallback == null:
			fallback = a
		if a.base_damage > 0:
			return a
	return fallback


## The action an ability made likelier (Hyping Up, Misty Secret, One's Ethos...), or null when
## the turn goes on as usual. Draws once from the encounter's rng, and only when some weight
## applies to an action that can be played: an individual with no weight consumes no random
## number, which keeps every earlier replay as it was. A weight is a probability added to the
## chance of that action; together they stop at 1. The remainder is the usual choice.
##
## Using an object is weighted but never played: rivals carry no objects yet (TODO).
func _weighted_action(
	individual: EncounterIndividual, manager: EncounterManager
) -> EncounterAction:
	if individual.action_weights.is_empty():
		return null
	var talk_targets: Array = manager.talk_targets(individual)
	var talk := 0.0
	if (
		manager.menu_kinds(individual).has(EncounterAction.Kind.TALK)
		and not talk_targets.is_empty()
	):
		talk = individual.action_bonus(EncounterAction.Kind.TALK)
	var meditate := individual.action_bonus(EncounterAction.Kind.MEDITATE)
	if talk <= 0.0 and meditate <= 0.0:
		return null
	var draw := manager.rng.randf()
	if draw < minf(talk, 1.0):
		var target = individual.weight_focus(EncounterAction.Kind.TALK, talk_targets)
		if target == null:
			target = talk_targets[0]
		return EncounterAction.of_kind(EncounterAction.Kind.TALK, [target])
	if draw < minf(talk + meditate, 1.0):
		return EncounterAction.of_kind(EncounterAction.Kind.MEDITATE, [individual])
	return null
