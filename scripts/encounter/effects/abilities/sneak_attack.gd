## Sneak Attack — zuk · Heat · medium · normal (10) · [damage]
## MÉCANIQUE : le dernier rival dans l'ordre du tour subit des dégâts.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var t = ctx.last_opponent_in_order()
	if t:
		ctx.deal_damage(t, ctx.base_damage())
