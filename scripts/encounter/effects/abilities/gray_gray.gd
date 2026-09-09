## Gray-Gray — basipik · Arcane · usage unique · [damage reduction/immunity]
## MÉCANIQUE : les rivaux ne voient plus la DEN ni la faiblesse du user (UI) jusqu'à la
## fin de la rencontre ; le user est immunisé aux dégâts Arcane jusqu'à son prochain tour.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	ctx.hide_weakness(ctx.user)
	ctx.request_ui(&"hide_user_den_weakness", {"fighter": ctx.user.species_id()})
	ctx.grant_immunity(ctx.user, [GameEnums.Energy.ARCANE])
