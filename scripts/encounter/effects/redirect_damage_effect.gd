## Redirige les prochains dégâts reçus (ex. Victimism) de l'utilisateur vers une cible.
class_name RedirectDamageEffect
extends AbilityEffect

func tag() -> StringName:
	return &"redirect next damage received"

func execute(ctx: EncounterContext) -> void:
	var to_target = ctx.targets[0] if not ctx.targets.is_empty() else null
	ctx.redirect_next_damage(ctx.user, to_target)
