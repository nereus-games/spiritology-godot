## Unfocused Complaint — niyat · Toxic · a lot · small (7) · [ETH loss, damage, limit actions]
## MÉCANIQUE : tout autre individu utilisant Méditer ce tour subit des dégâts, perd X ETH et
## ne peut pas Méditer au tour suivant. (Déclencheur « utilise Méditer » : approximé à tous
## les autres pour l'instant — à restreindre quand le système d'actions existera.)
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	for o in ctx.others():
		ctx.deal_damage(o, ctx.base_damage())  # TODO : seulement si o Médite ce tour
		ctx.drain_eth(o, ctx.dmg(&"small"))
		ctx.restrict_to(o, ["sauf Meditate"])
