## Tiresome Listing — érzélak · Toxic · normal · small (7) · [damage]
## MÉCANIQUE : la cible subit des dégâts pour chaque tranche de capacités enregistrées dans
## l'encyclopédie ; le user a 1/3 de chances d'en subir la moitié. (Nombre de capacités
## connues : approximé par le nombre d'espèces complétées.)
extends AbilityScript

func execute(ctx: EncounterContext) -> void:
	var known := maxi(ctx.completed_species.size(), 1)
	var t = ctx.primary()
	if t:
		ctx.deal_damage(t, ctx.base_damage() * known)
	if ctx.rng.randf() < 1.0 / 3.0:
		ctx.deal_damage(ctx.user, ctx.base_damage() * known / 2)
