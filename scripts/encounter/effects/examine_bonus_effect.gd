## Donne des infos / un bonus d'examen sur la cible (remplissage encyclopédie facilité).
class_name ExamineBonusEffect
extends AbilityEffect

const DEFAULT_AMOUNT := 1


func tag() -> StringName:
	return &"gives info/Examine bonus"


func execute(ctx: EncounterContext) -> void:
	for t in ctx.targets:
		ctx.grant_examine_bonus(t, DEFAULT_AMOUNT)
