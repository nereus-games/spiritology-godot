## Effet sur-mesure qui perturbe l'UI de rencontre (capacités spéciales).
## Exemples : Tumult déplace les éléments d'UI ; Anodyne Excess cache les stats des
## rivaux. Le `kind` est interprété par hud_encounter ; les paramètres passent par `data`.
class_name UiDisruptEffect
extends AbilityEffect

## Identifiant de la perturbation (ex. &"shuffle_ui", &"hide_rival_stats").
var kind: StringName

func _init(p_kind: StringName = &"") -> void:
	kind = p_kind

func tag() -> StringName:
	return &"ui"

func execute(ctx: EncounterContext) -> void:
	ctx.request_ui(kind, {"ability": ctx.ability.id})
