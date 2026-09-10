## Forces the target to Talk, opening the peaceful route.
class_name ForceTalkEffect
extends AbilityEffect


func tag() -> StringName:
	return &"force Talk"


func execute(ctx: EncounterContext) -> void:
	for t in ctx.targets:
		ctx.force_talk(t)
