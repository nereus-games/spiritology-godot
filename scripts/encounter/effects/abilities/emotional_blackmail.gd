## Emotional Blackmail — draka · Toxic · small (7) · [change weakness, damage, limit actions]
## MÉCANIQUE : le user impose au rival ciblé une action (Parler ou Donner un objet) ; s'il
## refuse, il subit des dégâts et tous les rivaux ne voient plus la faiblesse du user et de
## ses coéquipiers, laquelle est changée au hasard. (Choix/refus : cas du refus appliqué.)
extends AbilityScript

func execute(ctx: EncounterContext) -> void:
	var t = ctx.primary()
	if t:
		ctx.deal_damage(t, ctx.base_damage())  # cas du refus
	for m in ctx.team():
		ctx.hide_weakness(m)
		ctx.change_weakness(m)
