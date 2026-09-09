## Ghosting — fliritus · Toxic · mini · normal (10) · [damage]
## MÉCANIQUE : (le user doit avoir Parlé à un rival au tour précédent, encore présent) le
## user fuit la rencontre (seul) ; le rival à qui il a parlé subit des dégâts.
extends AbilityScript

func execute(ctx: EncounterContext) -> void:
	var t = ctx.primary()
	if t:
		ctx.deal_damage(t, ctx.base_damage())
	ctx.flee(ctx.user)
