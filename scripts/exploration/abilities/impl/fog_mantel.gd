## Fog Mantel — invisible des rivaux pour 5 à 8 cases (aléatoire).
##
## Doc Notion : « Become invisible from rivals for 5 to 8 tiles. Traps and encounters cancel
## this invisibility. » Le nombre de cases est tiré au hasard à chaque usage ; une rencontre
## ou l'activation d'un piège l'annule immédiatement (géré côté joueur / piège).
extends "res://scripts/exploration/abilities/exploration_ability.gd"


func use(ctx) -> bool:
	ctx.hide_from_rivals(ctx.rng.randi_range(5, 8))
	return true
