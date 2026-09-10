## Denial-Driven Fantasy — yilir · Arcane · mini · [recover ETH]
## MECHANIC: requires the user to have a weakness. It recovers X ETH per individual whose
## weakness differs, is absent, or is hidden; the turn order readout is hidden (a UI effect).
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var uw := ctx.weakness_of(ctx.user)
	if uw == GameEnums.Energy.NONE:
		return
	# An explicit loop rather than a filter() with a multi-line lambda: gdformat breaks the latter
	# when it is chained (.others().filter(...).size()), and the result no longer compiles. Same
	# meaning, and easier to read.
	var count := 0
	for f in ctx.others():
		var w := ctx.weakness_of(f)
		if w != uw or w == GameEnums.Energy.NONE or f.weakness_hidden:
			count += 1
	ctx.recover_eth(ctx.user, ctx.dmg(&"small") * count)
	ctx.request_ui(&"hide_turn_order_bar", {})
