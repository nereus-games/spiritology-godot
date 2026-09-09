## Troublesome Secret — basipik · mini (5) · [ETH loss, limit actions]
## MÉCANIQUE : le rival ciblé perd X ETH et ne peut plus utiliser Examiner ni aucun Objet
## jusqu'à la fin de la rencontre (ou jusqu'à ce qu'il Médite).
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var t = ctx.primary()
	if t:
		ctx.drain_eth(t, ctx.dmg(&"small"))
		ctx.restrict_to(t, ["sauf Examine", "sauf Object"])
