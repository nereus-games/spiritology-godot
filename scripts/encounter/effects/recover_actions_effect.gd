## Rend des actions à l'utilisateur (ou aux alliés).
class_name RecoverActionsEffect
extends AbilityEffect

const DEFAULT_AMOUNT := 1


func tag() -> StringName:
	return &"recover actions"


func execute(ctx: EncounterContext) -> void:
	ctx.recover_actions(ctx.user, DEFAULT_AMOUNT)
