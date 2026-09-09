## Catalogue/résolveur des effets de capacités (utilitaire statique, pas d'autoload).
##
## Chaque capacité a une logique UNIQUE, décrite dans sa page Notion. Le terrain est
## préparé ainsi :
##   - un script dédié par capacité dans `scripts/encounter/effects/abilities/<id>.gd`
##     (mécanique rappelée en docstring) — [method script_for] le résout par id ;
##   - tant qu'il n'est pas implémenté, son [AbilityScript] retombe sur les effets
##     GÉNÉRIQUES dérivés des `tags` (briques [AbilityEffect]), via [method tag_effects].
## Les `tags` ne sont qu'une catégorisation/garde-fou, pas la logique réelle.
##
## Statique (et non autoload) pour être joignable depuis n'importe quel contexte —
## y compris le comportement par défaut d'[AbilityScript], qui est un RefCounted.
##
## Usage (étape rencontre) :
##   EffectCatalog.script_for(ability).execute(ctx)
class_name EffectCatalog
extends RefCounted

const ABILITY_SCRIPTS_DIR := "res://scripts/encounter/effects/abilities/"

## Ordre d'application déterministe des effets génériques : les modificateurs
## (faiblesse, mitigation) s'appliquent avant les dégâts ; l'ordre du tour en fin.
const _ORDER: Array[StringName] = [
	&"change weakness",
	&"damage reduction/increase or immunity",
	&"damage",
	&"ETH loss",
	&"recover DEN",
	&"recover ETH",
	&"limit actions",
	&"recover actions",
	&"redirect next damage received",
	&"force Talk",
	&"gives info/Examine bonus",
	&"change next TO",
]

static var _tag_map: Dictionary = {}
static var _built := false


static func _ensure_built() -> void:
	if _built:
		return
	_built = true
	_tag_map = {
		&"damage": DamageEffect,
		&"change weakness": ChangeWeaknessEffect,
		&"ETH loss": EthLossEffect,
		&"recover DEN": RecoverDenEffect,
		&"recover ETH": RecoverEthEffect,
		&"damage reduction/increase or immunity": DamageModEffect,
		&"limit actions": LimitActionsEffect,
		&"recover actions": RecoverActionsEffect,
		&"change next TO": ChangeTurnOrderEffect,
		&"redirect next damage received": RedirectDamageEffect,
		&"force Talk": ForceTalkEffect,
		&"gives info/Examine bonus": ExamineBonusEffect,
	}


## Renvoie l'orchestrateur d'effet d'une capacité : son script dédié s'il existe,
## sinon un [AbilityScript] générique (comportement par tags).
static func script_for(ability: AbilityData) -> AbilityScript:
	if ability == null:
		return AbilityScript.new()
	var path := ABILITY_SCRIPTS_DIR + String(ability.id) + ".gd"
	if ResourceLoader.exists(path):
		var script: GDScript = load(path)
		var inst = script.new()
		if inst is AbilityScript:
			return inst
		push_warning("[EffectCatalog] %s n'étend pas AbilityScript." % path)
	return AbilityScript.new()


## Briques d'effets génériques dérivées des tags, dans l'ordre canonique. Utilisé par
## le comportement par défaut d'[AbilityScript] et par les scripts dédiés qui veulent
## réutiliser une partie du pipeline générique.
static func tag_effects(tags: PackedStringArray) -> Array[AbilityEffect]:
	_ensure_built()
	var present := {}
	for t in tags:
		present[StringName(t)] = true
	var out: Array[AbilityEffect] = []
	for tag in _ORDER:
		if present.has(tag) and _tag_map.has(tag):
			out.append(_tag_map[tag].new())
	for tag in present:
		if not _tag_map.has(tag):
			push_warning("[EffectCatalog] tag d'effet non géré : '%s'" % tag)
	return out


## Instancie une brique d'effet générique par tag (pour composition dans un script dédié).
static func effect(tag: StringName) -> AbilityEffect:
	_ensure_built()
	return _tag_map[tag].new() if _tag_map.has(tag) else null
