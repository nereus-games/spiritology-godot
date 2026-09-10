## Overrides the targets' exposed weakness. Normally the turn position decides it; this
## forces it regardless of where they stand.
class_name ChangeWeaknessEffect
extends AbilityEffect


func tag() -> StringName:
	return &"change weakness"


func execute(ctx: EncounterContext) -> void:
	for t in ctx.targets:
		ctx.change_weakness(t)
