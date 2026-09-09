## Glaciation — yilir · Crystal · small (7) · [damage, damage reduction/immunity]
## MÉCANIQUE : un rival subit des dégâts. Si la cible est dans l'équipe, elle annule tous
## les dégâts (et effets toxiques) du tour courant.
extends AbilityScript

func execute(ctx: EncounterContext) -> void:
	var t = ctx.primary()
	if t == null:
		return
	if t.is_player == ctx.user.is_player:
		ctx.grant_full_immunity(t)
	else:
		ctx.deal_damage(t, ctx.base_damage())
