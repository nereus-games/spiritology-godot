## Catatonia — niyat · Crystal · [examine bonus]
## MECHANIC: improves the user's Examine and Meditate next turn — more info, more ETH, more
## damage — with larger bonuses if it took damage this turn or the previous one, larger still if
## its own teammate dealt it. Scaling from the damage history is a TODO.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	ctx.grant_examine_bonus(ctx.user, 2)
	# TODO: boost Examine and Meditate next turn, scaled by the recent damage.
