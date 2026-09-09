## Absorption Guard — gélmi · Variable · small (7) · [damage, examine bonus, recover DEN]
## MÉCANIQUE : l'énergie = faiblesse actuelle du user. Un rival au hasard subit des dégâts ;
## si ce rival agit sur le user ce tour, le user l'Examine sans représailles et gagne X DEN
## (moitié du % d'info connu sur son espèce). (Condition « agit sur le user » : approximée.)
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	ctx.set_energy(ctx.weakness_of(ctx.user))
	var t = ctx.random_opponent()
	if t:
		ctx.deal_damage(t, ctx.base_damage())
		ctx.grant_examine_bonus(t, 1)
		ctx.recover_den(ctx.user, ctx.dmg(&"mini"))
