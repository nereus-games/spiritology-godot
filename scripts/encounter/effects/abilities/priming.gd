## Priming — fopin · Variable · medium · [change next TO, change weakness, immunity]
## MECHANIC: a targeted teammate moves first next turn and takes this ability's energy as its
## weakness; until the user's next turn, the teammates' damage steps up one tier
## (mini to small to normal to big) and they get more info.
##
## The tier step is a modifier on the teammates, the user excepted ("teammates" is
## [method EncounterContext.allies]) and applied to the base damage of whatever they deal.
## TODO: "they get more info" — Examine has no info figure to raise beyond the talents' 1.0
## factor, and the doc gives no amount; wire it where Recon Glide acts in
## [method EncounterManager._resolve_examine] once it does.
extends AbilityScript

const NextTurnModifiers := preload("res://scripts/encounter/effects/next_turn_modifiers.gd")


func execute(ctx: EncounterContext) -> void:
	var t = ctx.random_of(ctx.allies())
	if t:
		ctx.move_to_first(t)
		ctx.set_weakness(t, ctx.energy())
	for ally in ctx.allies():
		NextTurnModifiers.step_up_damage(ctx, ally)
