## Fournisseur d'action automatique (rivaux, et joueurs en résolution auto).
##
## Politique d'ÉCHAFAUDAGE, pas un design Notion : 1re capacité de rencontre offensive
## utilisable, sinon la 1re ; prend la première cible possible. Reprise telle quelle de
## l'ancien [EncounterManager] pour que les combats auto restent identiques après
## l'extraction de la décision. Le ciblage suit la règle commune du manager
## ([method EncounterManager.candidate_targets]), partagée avec le menu joueur.
class_name AutoAgent
extends EncounterAgent


func decide(fighter: EncounterFighter, manager: EncounterManager) -> EncounterAction:
	var ability := _choose_ability(fighter, manager)
	if ability == null:
		# Plus rien de jouable (tout consommé ou trop cher). Meditate n'a ni coût ni cible
		# et la doc l'accorde aussi aux rivaux : mieux vaut refaire de l'ETH que perdre
		# son tour. Talk et Use/Give Object leur sont également ouverts — l'IA ne les
		# joue pas encore (Talk dépend du système de dialogue, les objets n'existent pas).
		return EncounterAction.of_kind(EncounterAction.Kind.MEDITATE, [fighter])
	var targets := manager.candidate_targets(fighter, ability)
	return EncounterAction.use_ability(ability, [targets[0]] if not targets.is_empty() else [])


func _choose_ability(fighter: EncounterFighter, manager: EncounterManager) -> AbilityData:
	var fallback: AbilityData = null
	for a in manager.usable_abilities(fighter):
		if fallback == null:
			fallback = a
		if a.base_damage > 0:
			return a
	return fallback
