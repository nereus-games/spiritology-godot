## Deflection — kalilk · Random · medium · [change weakness, damage reduction/increase]
## MECHANIC: requires that the user has not used the same action twice. The target's weakness
## becomes this ability's energy until its next turn, and weakness-matching damage is doubled for
## everyone this turn.
##
## "This turn" is read like every other timed effect: until the user's next turn. What is doubled
## is the damage whose energy matches the weakness the victim exposes at the moment it is hit,
## the target's new one included.
extends AbilityScript

const OneOffs := preload("res://scripts/encounter/effects/one_off_rules.gd")

## "Doubled", from the doc.
const FACTOR := 2.0


func execute(ctx: EncounterContext) -> void:
	var t = ctx.primary()
	if t:
		ctx.set_weakness(t, ctx.energy())
	OneOffs.amplify_weakness_damage(ctx, FACTOR)
