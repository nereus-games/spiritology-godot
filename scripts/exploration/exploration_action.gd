## Descripteur d'une action contextuelle d'exploration proposée par un mécanisme.
##
## Produit par les hooks `on_tile_actions` / `on_adjacent_actions` des mécanismes (Dig,
## Recycle, Examine, Meditate, ouvrir une porte verrouillée…) et agrégé par
## [method DungeonManager.actions_for]. Consommé par la future surface d'actions
## d'exploration (HUD) : elle affiche [member label_key] via `tr()` et invoque
## [member callable] à la sélection.
##
## Pas de `class_name` (piège du cache CLI) : référencé par `preload`.
extends RefCounted

## Identifiant stable de l'action (ex. &"dig", &"recycle").
var id: StringName
## Clé de traduction du libellé affiché (convention UI_ACTION_<X>).
var label_key: String
## À invoquer quand le joueur choisit l'action (déjà liée à sa cible/acteur).
var callable: Callable


func _init(p_id: StringName, p_label_key: String, p_callable: Callable) -> void:
	id = p_id
	label_key = p_label_key
	callable = p_callable
