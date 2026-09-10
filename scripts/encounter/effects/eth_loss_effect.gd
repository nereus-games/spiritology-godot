## Drains ETH from the targets.
class_name EthLossEffect
extends AbilityEffect

## ## TODO: not a figure the doc gives.
const DEFAULT_AMOUNT := 5


func tag() -> StringName:
	return &"ETH loss"


func execute(ctx: EncounterContext) -> void:
	for t in ctx.targets:
		ctx.drain_eth(t, DEFAULT_AMOUNT)
