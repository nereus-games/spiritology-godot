## Restores DEN.
class_name RecoverDenEffect
extends AbilityEffect

const DEFAULT_AMOUNT := 5


func tag() -> StringName:
	return &"recover DEN"


func execute(ctx: EncounterContext) -> void:
	var amount := ctx.ability.base_damage if ctx.ability.base_damage > 0 else DEFAULT_AMOUNT
	ctx.recover_den(ctx.user, amount)
