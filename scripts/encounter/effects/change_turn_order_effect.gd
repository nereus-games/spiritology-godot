## Modifie l'ordre du tour à venir (Shuffle, Tumult…).
## Règle : si plusieurs effets d'ordre s'appliquent à un même individu dans un tour,
## seul le dernier compte ([EncounterTimeline] arbitre, à l'étape rencontre).
class_name ChangeTurnOrderEffect
extends AbilityEffect

func tag() -> StringName:
	return &"change next TO"

func execute(ctx: EncounterContext) -> void:
	ctx.change_turn_order({"ability": ctx.ability.id})
