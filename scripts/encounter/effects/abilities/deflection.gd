## Deflection — kalilk · Random · medium · [change weakness, damage reduction/increase]
## MECHANIC: requires that the user has not used the same action twice. The target's weakness
## becomes this ability's energy until its next turn, and weakness-matching damage is doubled for
## everyone this turn.
##
## "This turn" is read like every other timed effect: until the user's next turn. What is doubled
## is the damage whose energy matches the weakness the victim exposes at the moment it is hit,
## the target's new one included.
##
## "Has not used the same action twice" is read from the encounter history as: not unless the
## user's last two turns were the same action, the same kind of action and, for an ability, the
## same one (`EncounterHistory.Turn.same_action_as`; passing is no action). So someone who has
## Talked twice running, or used Shuffle twice, cannot Deflect; one Deflection in between, or any
## other action, lifts the ban. Like Moral Elevation, it is greyed out in the menu and left alone by
## the automatic agent while the condition fails, and does nothing if used regardless.
extends AbilityScript

const OneOffs := preload("res://scripts/encounter/effects/one_off_rules.gd")

## "Doubled", from the doc.
const FACTOR := 2.0


func is_usable(ctx: EncounterContext) -> bool:
	return not ctx.history.repeated_twice(ctx.user)


func execute(ctx: EncounterContext) -> void:
	if not is_usable(ctx):
		ctx.note(String(TranslationServer.translate("LOG_CONDITION_UNMET")))
		return
	var t = ctx.primary()
	if t:
		ctx.set_weakness(t, ctx.energy())
	OneOffs.amplify_weakness_damage(ctx, FACTOR)
