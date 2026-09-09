## Reuse (jézal) — « Single-use Encounter Abilities have a 50 % chance of being reusable
## after each use within the same encounter. »
##
## À chaque fois que le porteur consomme une capacité à usage unique, 50 % de chance
## qu'elle redevienne disponible pour cette rencontre. Le manager appelle [method
## wants_reuse] juste après avoir marqué la capacité consommée, et la « dé-consomme »
## si on renvoie true.
extends "res://scripts/encounter/talents/talent_script.gd"

## PLACEHOLDER assumé : Notion chiffre bien « 50 % », c'est donc la vraie valeur — mais
## isolée en constante comme les autres magnitudes, pour être ajustée au ressenti si besoin.
const REUSE_CHANCE := 0.5


func wants_reuse(manager, user, ability) -> bool:
	if user != owner or ability == null or not ability.single_use:
		return false
	return manager.rng.randf() < REUSE_CHANCE
