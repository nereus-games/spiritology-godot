## Fournit les actions d'exploration NON liées à une case : capacités d'exploration du duo
## et objets utilisables. Concaténées au menu d'actions du HUD à côté des actions de
## mécanismes ([method DungeonManager.actions_for]).
##
## Instancié (et conservé) par le HUD avec un [ExplorationContext] persistant : les [Callable]
## des actions pointent vers cette instance, qui doit donc rester vivante tant que le menu
## affiche ces actions.
##
## Pas de `class_name` (piège du cache CLI). Référence les autoloads (OK en jeu ; runtime-load
## dans les tests).
extends RefCounted

const ExplorationAction := preload("res://scripts/exploration/exploration_action.gd")
const Catalog := preload("res://scripts/exploration/abilities/exploration_ability_catalog.gd")
const Objects := preload("res://scripts/exploration/exploration_objects.gd")

var _ctx

func _init(ctx) -> void:
	_ctx = ctx

## Construit la liste d'actions (capacités d'exploration non utilisées + objets utilisables).
##
## ## TODO(doc « Game Design / Dungeon Exploration ») : l'action MEDITATE manque ici. La doc la
## range parmi les actions TOUJOURS disponibles en exploration — « Meditate – the duo recovers
## X ETH; can activate Meditation Gates » — alors qu'elle n'existe aujourd'hui que comme action
## CONTEXTUELLE d'une porte de méditation ([code]gateway.on_adjacent_actions[/code]), et qu'elle
## ne rend aucun ETH. Il faut : (1) l'ajouter à cette liste, (2) lui faire récupérer X ETH au duo
## (montant NON CHIFFRÉ par la doc ; la rencontre utilise 12, cf.
## [constant EncounterManager.MEDITATE_ETH]), (3) faire que la version portière ne soit plus
## qu'un effet de bord de la même action quand on fait face à une porte — sinon deux « méditer »
## cohabiteront dans le menu.
func build() -> Array:
	var actions: Array = []
	# Capacités d'exploration connues, pas encore utilisées cette visite.
	for id in Catalog.known_for_duo():
		if GameSession.is_exploration_ability_used(id):
			continue
		actions.append(ExplorationAction.new(id, _ability_label_key(id), Callable(self, "_run_ability").bind(id)))
	# Objets d'inventaire utilisables en exploration.
	for object_id in GameSession.inventory.keys():
		var data: ObjectData = GameData.object(object_id)
		if data != null and Objects.usable_in_exploration(data.effect):
			actions.append(ExplorationAction.new(object_id, data.name_key(), Callable(self, "_run_object").bind(object_id)))
	return actions

func _ability_label_key(id: StringName) -> String:
	var ab: AbilityData = GameData.ability(id)
	return ab.name_key() if ab != null else String(id)

func _run_ability(id: StringName) -> void:
	var ability = Catalog.script_for(id)
	if ability.use(_ctx):
		GameSession.mark_exploration_ability_used(id)

func _run_object(object_id: StringName) -> void:
	Objects.use_object(object_id, _ctx)
