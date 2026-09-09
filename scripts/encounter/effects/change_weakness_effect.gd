## Change la faiblesse active des cibles. La faiblesse dépend de la position dans
## l'ordre du tour ; cet effet la force/permute indépendamment de la position.
class_name ChangeWeaknessEffect
extends AbilityEffect

func tag() -> StringName:
	return &"change weakness"

func execute(ctx: EncounterContext) -> void:
	for t in ctx.targets:
		ctx.change_weakness(t)
