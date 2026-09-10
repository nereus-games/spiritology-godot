## Call of the Void — vérnal · Arcane · a lot · big (15) · [change weakness, damage]
## MECHANIC: every rival WITHOUT a weakness takes damage; the user's and its allies' weakness
## becomes Arcane.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	for r in ctx.opponents():
		if ctx.weakness_of(r) == GameEnums.Energy.NONE:
			ctx.deal_damage(r, ctx.base_damage())
	for a in ctx.team():
		ctx.set_weakness(a, GameEnums.Energy.ARCANE)
