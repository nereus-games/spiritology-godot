## Grants information about the target, filling its encyclopaedia page faster: the user Examines
## it, with `DEFAULT_AMOUNT` points of info bonus (`examine_yield.gd`).
class_name ExamineBonusEffect
extends AbilityEffect

const ExamineYield := preload("res://scripts/encounter/effects/examine_yield.gd")

## Placeholder: the tag carries no figure.
const DEFAULT_AMOUNT := 1


func tag() -> StringName:
	return &"gives info/Examine bonus"


func execute(ctx: EncounterContext) -> void:
	for t in ctx.targets:
		ExamineYield.examine(ctx, t, DEFAULT_AMOUNT)
