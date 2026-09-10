## Priming — fopin · Variable · medium · [change next TO, change weakness, immunity]
## MECHANIC: a targeted teammate moves first next turn and takes this ability's energy as its
## weakness; until the user's next turn, the teammates' damage steps up one tier
## (mini to small to normal to big) and they get more info. The outgoing-damage and info boosts
## are TODOs.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var t = ctx.random_of(ctx.allies())
	if t:
		ctx.move_to_first(t)
		ctx.set_weakness(t, ctx.energy())
