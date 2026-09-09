## Inflige les dégâts de base de la capacité aux cibles.
## Les modificateurs +36 %/condition (faiblesse, même Spiricosme, encyclopédie 100 %,
## même espèce) sont appliqués côté [EncounterContext.deal_damage] (à l'étape rencontre).
class_name DamageEffect
extends AbilityEffect


func tag() -> StringName:
	return &"damage"


func execute(ctx: EncounterContext) -> void:
	if ctx.ability.base_damage < 0:
		return
	for t in ctx.targets:
		ctx.deal_damage(t, ctx.ability.base_damage)
