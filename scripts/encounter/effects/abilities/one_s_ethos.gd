## One's Ethos — akturlin · Crystal · mini · small (7) · [damage]
## MÉCANIQUE : le premier rival dans l'ordre du tour subit des dégâts ; les rivaux de même
## origine que le user dialoguent +5 % plus souvent jusqu'à la fin (TODO).
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var t = ctx.first_opponent_in_order()
	if t:
		ctx.deal_damage(t, ctx.base_damage())
