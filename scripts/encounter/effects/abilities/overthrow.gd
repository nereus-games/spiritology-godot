## Overthrow — sopiark · Heat · a lot · small (7) · [damage, limit actions, recover DEN]
## MÉCANIQUE : le rival ciblé subit des dégâts ; s'il est dévitalisé, le user gagne X DEN ;
## la cible perd une action au tour suivant.
extends AbilityScript

func execute(ctx: EncounterContext) -> void:
	var t = ctx.primary()
	if t == null:
		return
	ctx.deal_damage(t, ctx.base_damage())
	if t.is_dissolved():
		ctx.recover_den(ctx.user, ctx.dmg(&"normal"))
	ctx.limit_actions(t, 1)
