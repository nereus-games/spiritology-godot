## Supplies the exploration actions NOT tied to a tile: the duo's exploration abilities and its
## usable objects. Appended to the HUD's action menu alongside the mechanism actions
## ([method DungeonManager.actions_for]).
##
## Instantiated — and kept — by the HUD with a persistent [ExplorationContext]: the actions'
## [Callable]s point at this instance, which therefore has to stay alive as long as the menu
## shows them.
##
## No `class_name` (the CLI class-cache trap). References the autoloads: fine in game, but tests
## have to load them at runtime.
extends RefCounted

const ExplorationAction := preload("res://scripts/exploration/exploration_action.gd")
const Catalog := preload("res://scripts/exploration/abilities/exploration_ability_catalog.gd")
const Objects := preload("res://scripts/exploration/exploration_objects.gd")

var _ctx


func _init(ctx) -> void:
	_ctx = ctx


## Builds the action list: unused exploration abilities plus usable objects.
##
## ## TODO: the MEDITATE action is missing here. The design doc lists it among the actions ALWAYS
## available in exploration — "Meditate – the duo recovers X ETH; can activate Meditation Gates"
## — whereas today it only exists as a meditation gateway's CONTEXTUAL action
## ([code]gateway.on_adjacent_actions[/code]), and gives back no ETH at all. What it takes:
## (1) add it to this list; (2) have it recover X ETH for the duo (the doc gives no number; the
## encounter uses 12, see [member BalanceData.meditate_eth]); (3) make the gateway version a side
## effect of that same action when facing a gateway — otherwise two "meditate" entries will sit
## in the menu side by side.
func build() -> Array:
	var actions: Array = []
	# Known exploration abilities, not yet used this visit.
	for id in Catalog.known_for_duo():
		if GameSession.is_exploration_ability_used(id):
			continue
		actions.append(
			ExplorationAction.new(
				id, _ability_label_key(id), Callable(self, "_run_ability").bind(id)
			)
		)
	# Inventory objects usable during exploration.
	for object_id in GameSession.inventory.keys():
		var data: ObjectData = GameData.object(object_id)
		if data != null and Objects.usable_in_exploration(data.effect):
			actions.append(
				ExplorationAction.new(
					object_id, data.name_key(), Callable(self, "_run_object").bind(object_id)
				)
			)
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
