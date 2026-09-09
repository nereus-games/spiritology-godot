## Dodge Blur — podargolo · Toxic · medium · mini/small · [damage, damage reduction]
## MÉCANIQUE : le user subit de petits dégâts ; tout rival utilisant Talk avant la fin du
## tour subit des dégâts (TODO) ; tous les autres dégâts infligés avant la fin du tour sont
## réduits de moitié.
extends AbilityScript

func execute(ctx: EncounterContext) -> void:
	ctx.deal_damage(ctx.user, ctx.dmg(&"mini"))
	ctx.modify_damage(ctx.user, 0.5)
	# TODO : tout rival utilisant Talk ce tour subit small ; mitigation pour tout le tour.
