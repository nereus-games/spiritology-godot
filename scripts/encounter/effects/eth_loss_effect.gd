## Draine de l'ETH (énergie/mana) aux cibles.
class_name EthLossEffect
extends AbilityEffect

## Montant drainé par défaut (à équilibrer).
const DEFAULT_AMOUNT := 5


func tag() -> StringName:
	return &"ETH loss"


func execute(ctx: EncounterContext) -> void:
	for t in ctx.targets:
		ctx.drain_eth(t, DEFAULT_AMOUNT)
