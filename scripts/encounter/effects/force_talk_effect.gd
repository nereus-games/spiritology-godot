## Force la cible à « parler » (Talk), ouvrant la voie pacifique / dialogue.
class_name ForceTalkEffect
extends AbilityEffect


func tag() -> StringName:
	return &"force Talk"


func execute(ctx: EncounterContext) -> void:
	for t in ctx.targets:
		ctx.force_talk(t)
