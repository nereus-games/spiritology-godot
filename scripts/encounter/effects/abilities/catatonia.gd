## Catatonia — niyat · Crystal · [examine bonus]
## MÉCANIQUE : améliore l'Examiner et le Méditer du user au tour suivant (plus d'info, plus
## d'ETH et de dégâts) ; bonus accrus s'il a subi des dégâts ce tour ou le précédent (encore
## plus si infligés par son coéquipier). (Modulation par historique de dégâts : TODO.)
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	ctx.grant_examine_bonus(ctx.user, 2)
	# TODO : amplifier Examine/Meditate au prochain tour, modulé par les dégâts récents.
