## Multiplies the next damage taken; 0 is immunity.
## Whether it is a shield on oneself or a hex on the enemy depends on the ability, and is
## settled by that ability's own script when it has one.
class_name DamageModEffect
extends AbilityEffect

## Below 1 mitigates, above 1 amplifies, 0 is immunity.
const DEFAULT_FACTOR := 0.5


func tag() -> StringName:
	return &"damage reduction/increase or immunity"


func execute(ctx: EncounterContext) -> void:
	for t in ctx.targets:
		ctx.modify_damage(t, DEFAULT_FACTOR)
