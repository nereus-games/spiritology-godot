## Business Card — hibulus · Variable · usage unique · [force Talk, recover DEN]
## MÉCANIQUE : au tour suivant, les rivaux de même origine que le user Parlent plus souvent
## avec lui (TODO) ; le user gagne X DEN chaque fois qu'un rival lui Parle (déclencheur TODO).
extends AbilityScript

func execute(ctx: EncounterContext) -> void:
	ctx.recover_den(ctx.user, ctx.dmg(&"small"))
	# TODO : bonus de dialogue (même origine) + gain de DEN quand un rival Parle au user.
