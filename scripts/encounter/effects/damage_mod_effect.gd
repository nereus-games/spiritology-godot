## Réduction / augmentation des dégâts, ou immunité (facteur ; 0 = immunité).
## Le sens exact (buff défensif sur soi vs debuff offensif sur l'ennemi) dépend de la
## capacité : à raffiner par surcharge sur-mesure dans le registre si besoin.
class_name DamageModEffect
extends AbilityEffect

## Facteur par défaut (placeholder à équilibrer). < 1 réduit, > 1 augmente, 0 = immunité.
const DEFAULT_FACTOR := 0.5

func tag() -> StringName:
	return &"damage reduction/increase or immunity"

func execute(ctx: EncounterContext) -> void:
	for t in ctx.targets:
		ctx.modify_damage(t, DEFAULT_FACTOR)
