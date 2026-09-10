## Restores ETH.
class_name RecoverEthEffect
extends AbilityEffect

const DEFAULT_AMOUNT := 5


func tag() -> StringName:
	return &"recover ETH"


func execute(ctx: EncounterContext) -> void:
	ctx.recover_eth(ctx.user, DEFAULT_AMOUNT)
