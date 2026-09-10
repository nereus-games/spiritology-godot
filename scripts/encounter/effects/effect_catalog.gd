## Resolves an ability to the code that runs it.
##
## Every ability has a UNIQUE mechanic, described on its own page in the design doc, and
## its own script in `scripts/encounter/effects/abilities/<id>.gd` — [method script_for]
## finds it by id. Until that mechanic is written, the script falls back on the GENERIC
## effects derived from the ability's `tags` ([method tag_effects]).
##
## The tags are a categorisation and a guard rail, never the real logic.
##
## Static rather than an autoload so it can be reached from anywhere — including
## [AbilityScript]'s own default, which is a RefCounted with no scene tree around it.
##
##   EffectCatalog.script_for(ability).execute(ctx)
class_name EffectCatalog
extends RefCounted

const ABILITY_SCRIPTS_DIR := "res://scripts/encounter/effects/abilities/"

## A fixed order for the generic effects, so a fallback is at least deterministic:
## modifiers (weakness, mitigation) before damage, reordering last.
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


## The ability's own script if it has one, otherwise a plain [AbilityScript] that will
## fall back on the tags.
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


## The generic bricks a set of tags implies, in the canonical order. Used by
## [AbilityScript]'s default, and by written mechanics that want part of the pipeline.
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


## One brick by tag, for a written mechanic to compose with.
static func effect(tag: StringName) -> AbilityEffect:
	_ensure_built()
	return _tag_map[tag].new() if _tag_map.has(tag) else null
