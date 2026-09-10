## Changes the coming turn order (Shuffle, Tumult).
## When several such effects land in one turn, only the last counts — [EncounterTimeline]
## holds the requests and settles it at the end of the turn.
class_name ChangeTurnOrderEffect
extends AbilityEffect


func tag() -> StringName:
	return &"change next TO"


func execute(ctx: EncounterContext) -> void:
	ctx.change_turn_order({"ability": ctx.ability.id})
