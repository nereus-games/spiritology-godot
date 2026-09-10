## Disturbs the encounter UI itself — Tumult shuffles its elements, Anodyne Excess hides
## the rivals' stats. The UI decides what each `kind` means; `data` carries its parameters.
class_name UiDisruptEffect
extends AbilityEffect

## Which disturbance to ask for.
var kind: StringName


func _init(p_kind: StringName = &"") -> void:
	kind = p_kind


func tag() -> StringName:
	return &"ui"


func execute(ctx: EncounterContext) -> void:
	ctx.request_ui(kind, {"ability": ctx.ability.id})
