## Takes actions away from the targets on their coming turns.
class_name LimitActionsEffect
extends AbilityEffect

const DEFAULT_AMOUNT := 1


func tag() -> StringName:
	return &"limit actions"


func execute(ctx: EncounterContext) -> void:
	for t in ctx.targets:
		ctx.limit_actions(t, DEFAULT_AMOUNT)
