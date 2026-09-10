## Headless check on the integrity of `data/` and `translations/`. Exits 1 if any of it
## regresses.
##
## Run with: Godot --headless --path . res://scenes/dev/data_integrity_check.tscn
## As a start scene rather than --script; see geometry_check.gd.
##
## WHY this check matters: the .tres and .po files are WRITTEN BY HAND. While a generator
## produced them their consistency was guaranteed by construction; it no longer is. A typo in a
## slug, a forgotten translation key or an out-of-range enum raise NO error at load — the game
## starts and misbehaves later. This is where that has to stop, and nowhere else.
##
## What counts as a FAILURE: any internal inconsistency — a dead reference, a missing key, an
## en/fr divergence, an out-of-range enum. What is only a COUNT: known content gaps, such as
## descriptions not yet written or sprites not yet drawn. A check that fails on content still to
## be produced stops signalling regressions.
extends Node

const SPECIES_DIR := "res://data/species/"
const ABILITIES_DIR := "res://data/abilities/"
const OBJECTS_DIR := "res://data/objects/"
const DUNGEONS_DIR := "res://data/dungeons/"
const SCENARIOS_DIR := "res://data/scenarios/"
const SPRITE_DIR := "res://assets/sprites/spirimonsters/"

const PO_EN := "res://translations/en.po"
const PO_FR := "res://translations/fr.po"

## Key prefixes backed by data: each must have its .tres, and the other way round. UI_* keys are
## written by hand and out of scope.
const DATA_PREFIXES := ["SPECIES_", "ABILITY_", "TALENT_", "OBJECT_", "DUNGEON_", "SCENARIO_"]

## Code constants holding species slugs whose NAME does not say so. The sweep only picks up
## constants with "SPECIES" in the name — hence the name of THIS one, which has to escape it so
## it does not check itself. The exceptions are listed by hand rather than renamed: renaming game
## code to suit a test is a test dressed up as a refactor.
const EXTRA_SLUG_CONSTANTS := {
	"res://scripts/exploration/mechanisms/examinable_decor.gd": ["POOLS"],
}

var _fails: Array[String] = []

var _species: Dictionary = {}  ## id -> SpeciesData
var _abilities: Dictionary = {}  ## id -> AbilityData
var _talents: Dictionary = {}  ## id -> TalentData
var _objects: Dictionary = {}  ## id -> ObjectData
var _dungeons: Dictionary = {}  ## id -> DungeonConfig
var _scenarios: Dictionary = {}  ## id -> ScenarioData (the exploration test scenarios)


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  OK   %s" % label)
	else:
		print("  FAIL %s" % label)
		_fails.append(label)


## A failure listing the offenders, truncated: thirty slugs in a heap drown the useful part.
func _check_empty(offenders: Array, label: String) -> void:
	if offenders.is_empty():
		_check(true, label)
		return
	var shown := offenders.slice(0, 6)
	var suffix := "" if offenders.size() <= 6 else " … (+%d)" % (offenders.size() - 6)
	_check(false, "%s — %s%s" % [label, ", ".join(shown), suffix])


func _ready() -> void:
	_run_all()


func _run_all() -> void:
	await get_tree().process_frame  # let the autoloads (GameData) load
	_check_loading()
	_check_enums()
	_check_balance()
	_check_cross_refs()
	_check_code_species_refs()
	_check_translations()
	_check_sprites()
	print("")
	if _fails.is_empty():
		print("ALL OK")
	else:
		print("FAILURES: %s" % [_fails])
	get_tree().quit(0 if _fails.is_empty() else 1)


# --------------------------------------------------------------------------
# Loading: every .tres loads, types, and has an id matching its file name
# --------------------------------------------------------------------------


func _check_loading() -> void:
	print("— loading —")
	var unloadable: Array = []
	var untyped: Array = []
	var mismatched: Array = []
	var total := 0
	for dir_path in [SPECIES_DIR, ABILITIES_DIR, OBJECTS_DIR, DUNGEONS_DIR, SCENARIOS_DIR]:
		for file_name in _tres_files(dir_path):
			total += 1
			var path: String = dir_path + file_name
			var res := load(path)
			if res == null:
				unloadable.append(file_name)
				continue
			var registry = _registry_for(res)
			if registry == null:
				untyped.append(file_name)
				continue
			if not ("id" in res) or String(res.id) == "":
				untyped.append("%s (empty id)" % file_name)
				continue
			# The file name is authoritative elsewhere in the code (`data/species/%s.tres` % slug,
			# `assets/.../%s.png` % slug), so an id that drifts from it breaks those lookups
			# without a word. Compared through key_token so the file name's Unicode form does not
			# trip it up — macOS writes accents in NFD, not NFC.
			if GameEnums.key_token(file_name.get_basename()) != GameEnums.key_token(res.id):
				mismatched.append("%s != id '%s'" % [file_name, res.id])
				continue
			registry[res.id] = res
	_check(total > 0, "%d resources found under data/" % total)
	_check_empty(unloadable, "every resource loads")
	_check_empty(untyped, "every resource has a known type and id")
	_check_empty(mismatched, "each resource's id matches its file name")
	print(
		(
			"  ·    %d species, %d abilities, %d talents, %d objects, %d dungeons, %d scenarios"
			% [
				_species.size(),
				_abilities.size(),
				_talents.size(),
				_objects.size(),
				_dungeons.size(),
				_scenarios.size()
			]
		)
	)
	# GameData redoes this sorting at boot with its own routing logic, so a discrepancy would mean
	# the autoload is not seeing the same data as this check.
	_check(
		GameData.all_species().size() == _species.size(),
		"GameData sees the same species (%d)" % GameData.all_species().size()
	)


func _tres_files(dir_path: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".tres"):
			out.append(f)
	out.sort()
	return out


## The registry matching a resource's type, or null when the type is unknown.
func _registry_for(res: Resource):
	if res is SpeciesData:
		return _species
	if res is TalentData:
		return _talents
	if res is AbilityData:
		return _abilities
	if res is ObjectData:
		return _objects
	if res is DungeonConfig:
		return _dungeons
	if res is ScenarioData:
		return _scenarios
	return null


# --------------------------------------------------------------------------
# Enums: the .tres store bare integers, so an out-of-range value goes unnoticed
# --------------------------------------------------------------------------


func _check_enums() -> void:
	print("— enums —")
	var bad: Array = []
	for id in _species:
		var sp: SpeciesData = _species[id]
		_expect_enum(bad, id, "spiricosm", sp.spiricosm, GameEnums.Spiricosm)
		for field in ["weakness_first", "weakness_middle", "weakness_last"]:
			_expect_enum(bad, id, field, sp.get(field), GameEnums.Energy)
		if sp.talker_chance < 0.0 or sp.talker_chance > 1.0:
			bad.append("%s.talker_chance = %.2f outside [0, 1]" % [id, sp.talker_chance])
	for id in _abilities:
		var ab: AbilityData = _abilities[id]
		_expect_enum(bad, id, "type", ab.type, GameEnums.AbilityType)
		_expect_enum(bad, id, "energy", ab.energy, GameEnums.Energy)
		_expect_enum(bad, id, "cost", ab.cost, GameEnums.Cost)
	for id in _objects:
		_expect_enum(bad, id, "effect", _objects[id].effect, GameEnums.ObjectEffect)
	_check_empty(bad, "every enum value is within range")


func _expect_enum(bad: Array, id, field: String, value, enum_dict: Dictionary) -> void:
	if not enum_dict.values().has(int(value)):
		bad.append("%s.%s = %s" % [id, field, value])


# --------------------------------------------------------------------------
# Balance: numbers meant to be tuned, but not to just anything
# --------------------------------------------------------------------------


## `data/balance.tres` exists to be TUNED by hand — that is exactly why it lives in data. These
## bounds therefore impose no value: they only forbid the ones that would break the game silently
## (a negative cost would give ETH back, a base DEN of zero would dissolve everyone on turn one).
func _check_balance() -> void:
	print("— balance —")
	var b := BalanceData.current()
	_check(b != null, "data/balance.tres loads")
	if b == null:
		return
	var bad: Array = []
	for field in [
		"base_den", "base_eth", "damage_mini", "damage_small", "damage_normal", "damage_big"
	]:
		if int(b.get(field)) <= 0:
			bad.append("%s = %s (must be > 0)" % [field, b.get(field)])
	for field in [
		"cost_mini", "cost_normal", "cost_medium", "cost_a_lot", "object_heal_den", "meditate_eth"
	]:
		if int(b.get(field)) < 0:
			bad.append("%s = %s (must be >= 0)" % [field, b.get(field)])
	for field in ["modifier_per_condition", "meditate_damage_bonus"]:
		if float(b.get(field)) < 0.0:
			bad.append("%s = %s (must be >= 0)" % [field, b.get(field)])
	_check_empty(bad, "the balance values stay playable")


# --------------------------------------------------------------------------
# Cross-references: a dead slug only shows up when something follows it
# --------------------------------------------------------------------------


func _check_cross_refs() -> void:
	print("— references —")
	var dead: Array = []
	for id in _species:
		var sp: SpeciesData = _species[id]
		if sp.talent != &"" and not _talents.has(sp.talent):
			dead.append("%s.talent → %s" % [id, sp.talent])
		for field in ["origin_abilities", "also_used_abilities", "encyclopaedia_abilities"]:
			for aid in sp.get(field):
				if not _abilities.has(aid):
					dead.append("%s.%s → %s" % [id, field, aid])
		if sp.forlorn_ability != &"" and not _abilities.has(sp.forlorn_ability):
			dead.append("%s.forlorn_ability → %s" % [id, sp.forlorn_ability])
		for oid in sp.loot:
			if not _objects.has(oid):
				dead.append("%s.loot → %s" % [id, oid])
	for id in _talents:
		var td: TalentData = _talents[id]
		if td.owner_species != &"" and not _species.has(td.owner_species):
			dead.append("%s.owner_species → %s" % [id, td.owner_species])
	for id in _abilities:
		var ab: AbilityData = _abilities[id]
		if ab.origin_species != &"" and not _species.has(ab.origin_species):
			dead.append("%s.origin_species → %s" % [id, ab.origin_species])
	for id in _objects:
		var ob: ObjectData = _objects[id]
		for field in ["species_id", "secondary_species_id"]:
			var sid = ob.get(field)
			if sid != &"" and not _species.has(sid):
				dead.append("%s.%s → %s" % [id, field, sid])
	for id in _dungeons:
		var dg: DungeonConfig = _dungeons[id]
		for sid in dg.possible_species:
			if not _species.has(sid):
				dead.append("%s.possible_species → %s" % [id, sid])
	_check_empty(dead, "no dead reference between data")

	# The 1:1 talent-to-species relation: every talent is carried, every carrier is acknowledged.
	var unowned: Array = []
	for id in _talents:
		var owner: StringName = _talents[id].owner_species
		if owner == &"" or not _species.has(owner) or _species[owner].talent != id:
			unowned.append("%s (owner_species=%s)" % [id, owner])
	_check_empty(unowned, "every talent is carried by the species that declares it")


# --------------------------------------------------------------------------
# Species named by CODE: a dead slug there triggers nothing at all
# --------------------------------------------------------------------------


## The exploration mechanisms hard-code lists of species: which spirimonster litter can reveal,
## which decor points at whom. A wrong slug there is INVISIBLE — the list simply gives nothing,
## with no error. The `.tres` cross-reference check does not see them, since they are not in the
## data.
##
## The loaded scripts' constants are read rather than parsing GDScript: the constant table is
## exact where a regular expression would only approximate.
func _check_code_species_refs() -> void:
	print("— species named by code —")
	var dead: Array = []
	var checked := 0
	for path in _gd_files("res://scripts/"):
		var script := load(path) as GDScript
		if script == null:
			continue
		var extras: Array = EXTRA_SLUG_CONSTANTS.get(path, [])
		for name in script.get_script_constant_map():
			if not (String(name).contains("SPECIES") or extras.has(String(name))):
				continue
			for slug in _flatten_slugs(script.get_script_constant_map()[name]):
				checked += 1
				if not _species.has(slug):
					dead.append("%s.%s → %s" % [path.get_file(), name, slug])
	_check(checked > 0, "%d species slugs named in the code" % checked)
	_check_empty(dead, "every species named by code exists in data/species/")


## The slugs held in a constant, whether it is an array or a dictionary of arrays — the decor
## pools are indexed by type.
func _flatten_slugs(value) -> Array:
	var out: Array = []
	if value is Array:
		for v in value:
			if v is StringName or v is String:
				out.append(StringName(v))
	elif value is Dictionary:
		for k in value:
			out.append_array(_flatten_slugs(value[k]))
	return out


func _gd_files(dir_path: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for d in dir.get_directories():
		out.append_array(_gd_files(dir_path.path_join(d)))
	for f in dir.get_files():
		if f.ends_with(".gd"):
			out.append(dir_path.path_join(f))
	out.sort()
	return out


# --------------------------------------------------------------------------
# Translations: a missing key breaks nothing, it just displays its own name
# --------------------------------------------------------------------------


func _check_translations() -> void:
	print("— translations —")
	var en := _parse_po(PO_EN)
	var fr := _parse_po(PO_FR)
	_check(not en["keys"].is_empty() and not fr["keys"].is_empty(), "both .po files parse")
	_check_empty(en["dupes"] + fr["dupes"], "no duplicate msgid")

	# en/fr parity: a key translated on one side only shows its raw slug in the other language.
	var only_en: Array = []
	var only_fr: Array = []
	for k in en["keys"]:
		if not fr["keys"].has(k):
			only_en.append(k)
	for k in fr["keys"]:
		if not en["keys"].has(k):
			only_fr.append(k)
	_check_empty(only_en + only_fr, "en.po and fr.po carry the same keys")

	# Every piece of data has its name translated, in both languages.
	var missing: Array = []
	for registry in [_species, _abilities, _talents, _objects, _dungeons, _scenarios]:
		for id in registry:
			var key: String = registry[id].name_key()
			for po in [["en", en], ["fr", fr]]:
				if not po[1]["keys"].has(key):
					missing.append("%s (%s)" % [key, po[0]])
	_check_empty(missing, "every piece of data has its name translated in en and fr")

	# The converse: an orphaned data key outlives the data it belonged to and stays invisible.
	# With no idempotent generator to rewrite the .po files, this is the only way to see it.
	var expected := {}
	for registry in [_species, _abilities, _talents, _objects, _dungeons, _scenarios]:
		for id in registry:
			var res = registry[id]
			expected[res.name_key()] = true
			for method in ["desc_key", "description_key"]:
				if res.has_method(method):
					expected[res.call(method)] = true
	var orphans: Array = []
	for k in en["keys"]:
		if _is_data_key(k) and not expected.has(k):
			orphans.append(k)
	_check_empty(orphans, "no orphaned data key in the .po files")

	# Counts, not failures: content still to write, not inconsistency.
	print(
		(
			"  ·    %d keys en / %d fr; %d empty msgstr en, %d fr"
			% [en["keys"].size(), fr["keys"].size(), en["empty"], fr["empty"]]
		)
	)


func _is_data_key(key: String) -> bool:
	for prefix in DATA_PREFIXES:
		if key.begins_with(prefix):
			return true
	return false


## Minimal .po reading: msgid/msgstr on one line, which is what our files write. Multi-line
## continuations, as in the header, are ignored, with no effect on the keys.
func _parse_po(path: String) -> Dictionary:
	var out := {"keys": {}, "dupes": [], "empty": 0}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	var pending := ""
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line.begins_with('msgid "') and line.ends_with('"'):
			var key := line.substr(7, line.length() - 8)
			if key == "":
				pending = ""  # the .po header
				continue
			if out["keys"].has(key):
				out["dupes"].append(key)
			out["keys"][key] = ""
			pending = key
		elif line.begins_with('msgstr "') and line.ends_with('"') and pending != "":
			var value := line.substr(8, line.length() - 9)
			out["keys"][pending] = value
			if value == "":
				out["empty"] += 1
			pending = ""
	return out


# --------------------------------------------------------------------------
# Sprites: a declared path must exist; declaring none is simply missing art
# --------------------------------------------------------------------------


func _check_sprites() -> void:
	print("— sprites —")
	var broken: Array = []
	var without := 0
	for id in _species:
		var sp: SpeciesData = _species[id]
		var declared := false
		for field in ["sprite_idle", "sprite_forlorn"]:
			var path: String = sp.get(field)
			if path == "":
				continue
			declared = true
			if not ResourceLoader.exists(path):
				broken.append("%s.%s → %s" % [id, field, path])
		if not declared:
			without += 1
	_check_empty(broken, "every declared sprite exists on disk")
	print("  ·    %d species with no sprite declared (art still to produce)" % without)
