## Supplies the exploration actions NOT tied to a tile: Meditate, the duo's exploration abilities
## and its usable objects. Merged into the HUD's action menu with the mechanism actions
## ([method DungeonManager.actions_for]) by [method combine].
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

## Id of the Meditate action, shared with the meditation gateway's contextual one.
const MEDITATE_ID := &"meditate"

var _ctx


func _init(ctx) -> void:
	_ctx = ctx


## Merges the contextual actions of the tile being faced with the ones offered everywhere: returns
## `contextual` without any meditation gateway entry, followed by [method build]. The gateway's own
## Meditate is not a second menu entry but a side effect of the generic one, so it is stripped here
## and handed to [method build].
func combine(contextual: Array) -> Array:
	var actions: Array = []
	var gateway_meditation = null
	for action in contextual:
		if action.id == MEDITATE_ID:
			gateway_meditation = action
		else:
			actions.append(action)
	actions.append_array(build(gateway_meditation))
	return actions


## Builds the action list: Meditate, always on offer, then the unused exploration abilities and the
## usable objects. `gateway_meditation` is the facing meditation gateway's own Meditate action, if
## there is one: choosing Meditate then also counts towards opening that gateway.
func build(gateway_meditation = null) -> Array:
	var actions: Array = [
		ExplorationAction.new(
			MEDITATE_ID,
			"UI_ACTION_MEDITATE",
			Callable(self, "_run_meditate").bind(gateway_meditation)
		)
	]
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


## Meditate: the duo recovers [member BalanceData.meditate_eth] ETH each and, when facing a
## meditation gateway, the meditation counts towards opening it.
func _run_meditate(gateway_meditation) -> void:
	if _refused():
		return
	_ctx.recover_duo_eth(BalanceData.current().meditate_eth)
	if gateway_meditation != null and gateway_meditation.callable.is_valid():
		gateway_meditation.callable.call()


## PSY rung 4: poison forbids Meditate and objects. The entries stay on the menu, and trying one
## shows the warning.
func _refused() -> bool:
	if not _ctx.poison_forbids_actions():
		return false
	_ctx.refuse_poisoned_action()
	return true


func _run_ability(id: StringName) -> void:
	var ability = Catalog.script_for(id)
	if ability.use(_ctx):
		GameSession.mark_exploration_ability_used(id)


func _run_object(object_id: StringName) -> void:
	if _refused():
		return
	Objects.use_object(object_id, _ctx)
