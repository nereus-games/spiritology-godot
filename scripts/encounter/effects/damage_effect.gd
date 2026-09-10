## Deals the ability's base damage.
## The per-condition modifiers — weakness struck, shared Spiricosm, completed page, same
## species — are applied by [method EncounterContext.deal_damage], not here.
class_name DamageEffect
extends AbilityEffect


func tag() -> StringName:
	return &"damage"


func execute(ctx: EncounterContext) -> void:
	if ctx.ability.base_damage < 0:
		return
	for t in ctx.targets:
		ctx.deal_damage(t, ctx.ability.base_damage)
