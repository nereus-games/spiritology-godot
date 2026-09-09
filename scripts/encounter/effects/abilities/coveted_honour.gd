## Coveted Honour — fopin · Arcane · mini (5) · [damage, recover DEN]
## MÉCANIQUE : le dernier (dans l'ordre du tour) parmi le user et ses alliés gagne X DEN ;
## un rival au hasard subit des dégâts.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var ally = ctx.last_of_team_in_order()
	if ally:
		ctx.recover_den(ally, ctx.dmg(&"normal"))
	var t = ctx.random_opponent()
	if t:
		ctx.deal_damage(t, ctx.base_damage())
