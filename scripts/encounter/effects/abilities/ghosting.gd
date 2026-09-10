## Ghosting — fliritus · Toxic · mini · normal (10) · [damage]
## MECHANIC: requires the user to have Talked to a rival on the previous turn, and that rival to
## still be around. The user flees the encounter alone, and the rival it spoke to takes damage.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var t = ctx.primary()
	if t:
		ctx.deal_damage(t, ctx.base_damage())
	ctx.flee(ctx.user)
