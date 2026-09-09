## Saving Face — sénskor · Variable · medium · normal (10) · [damage, recover DEN]
## MÉCANIQUE : une cible de l'équipe récupère X DEN, plus Y DEN par coéquipier de même
## faiblesse ; le user a 1/3 de chances de subir des dégâts Toxiques (1/2 si sa faiblesse
## est Toxique).
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var t = ctx.user  # cible dans l'équipe
	var w := ctx.weakness_of(t)
	var same := ctx.team().filter(func(f): return f != t and ctx.weakness_of(f) == w).size()
	ctx.recover_den(t, ctx.dmg(&"normal") + ctx.dmg(&"small") * same)
	var chance := 0.5 if ctx.weakness_of(ctx.user) == GameEnums.Energy.TOXIC else 1.0 / 3.0
	if ctx.rng.randf() < chance:
		ctx.set_energy(GameEnums.Energy.TOXIC)
		ctx.deal_damage(ctx.user, ctx.dmg(&"small"))
