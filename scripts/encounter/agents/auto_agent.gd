## Plays an individual automatically — every rival, and players in headless runs.
##
## SCAFFOLDING, not a design from the doc: the first usable offensive ability, else the
## first usable one at all, aimed at the first legal target. Targeting goes through the
## manager's shared rule ([method EncounterManager.candidate_targets]), the same one the
## player's menu uses, so the two cannot drift apart.
class_name AutoAgent
extends EncounterAgent


func decide(individual: EncounterIndividual, manager: EncounterManager) -> EncounterAction:
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
		if fallback == null:
			fallback = a
		if a.base_damage > 0:
			return a
	return fallback
