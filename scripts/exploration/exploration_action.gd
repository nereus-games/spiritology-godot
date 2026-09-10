## Describes one contextual exploration action offered by a mechanism.
##
## Produced by the mechanisms' `on_tile_actions` and `on_adjacent_actions` hooks — Dig, Recycle,
## Examine, Meditate, unlocking a gateway — and aggregated by
## [method DungeonManager.actions_for]. The HUD's exploration action surface consumes it: it
## shows [member label_key] through `tr()` and invokes [member callable] on selection.
##
## No `class_name` (the CLI class-cache trap): referenced by `preload`.
extends RefCounted

## Stable identifier for the action, such as &"dig" or &"recycle".
var id: StringName
## Translation key of the label shown. The convention is UI_ACTION_<X>.
var label_key: String
## Invoked when the player picks the action. Already bound to its target and actor.
var callable: Callable


func _init(p_id: StringName, p_label_key: String, p_callable: Callable) -> void:
	id = p_id
	label_key = p_label_key
	callable = p_callable
