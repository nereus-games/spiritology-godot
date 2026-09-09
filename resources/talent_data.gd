## Schéma d'un Talent : passif propre à une espèce.
##
## Un talent par espèce, non apprenable et non encyclopédiable. Se cumule si le duo
## comporte deux individus de la même espèce. Séparé d'[AbilityData] car les talents
## n'ont ni énergie, ni coût, ni dégâts directs et obéissent à une logique distincte.
## Instances .tres dans `data/abilities/` (lignes Type=Talent côté Notion), éditées à
## la main — cf. `docs/data-model.md`.
class_name TalentData
extends Resource

## Identifiant slug stable (ex. "restore", "reveal_traps"). Base des clés de trad.
@export var id: StringName

## Espèce qui porte ce talent (slug). Relation 1:1 avec un [SpeciesData].
@export var owner_species: StringName

## Tags décrivant l'effet passif, pour le moteur d'effets.
@export var tags: PackedStringArray = PackedStringArray()

## Le cumul de deux talents identiques (duo de même espèce) est-il pertinent /
## explicitement défini pour ce talent.
@export var stacks_in_duo: bool = true


## Clé de traduction du nom. Convention : TALENT_<ID_MAJ>_NAME.
func name_key() -> String:
	return "TALENT_%s_NAME" % GameEnums.key_token(id)


## Clé de traduction de la description. Convention : TALENT_<ID_MAJ>_DESC.
func desc_key() -> String:
	return "TALENT_%s_DESC" % GameEnums.key_token(id)
