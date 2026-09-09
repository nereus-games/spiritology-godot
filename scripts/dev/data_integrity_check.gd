## Vérification headless de l'intégrité des données de `data/` et `translations/`.
## Sort en code 1 si l'une d'elles régresse.
##
## Lancé par : Godot --headless --path . res://scenes/dev/data_integrity_check.tscn
## (scène de démarrage, et non --script : voir geometry_check.gd.)
##
## POURQUOI ce check est central : les .tres et les .po sont ÉCRITS À LA MAIN. Tant qu'un
## générateur les produisait, leur cohérence était garantie par construction ; elle ne
## l'est plus. Une faute de frappe dans un slug, une clé de traduction oubliée ou un enum
## hors bornes ne lèvent AUCUNE erreur au chargement — le jeu démarre et se comporte mal
## plus tard. C'est ici, et nulle part ailleurs, que ça doit s'arrêter.
##
## Ce qui est un ÉCHEC : toute incohérence interne (référence morte, clé manquante,
## divergence en/fr, enum hors plage). Ce qui n'est qu'un DÉCOMPTE : les manques de
## contenu connus (descriptions non rédigées, sprites non dessinés) — un check qui échoue
## sur du contenu à produire ne signale plus les régressions.
extends Node

const SPECIES_DIR := "res://data/species/"
const ABILITIES_DIR := "res://data/abilities/"
const OBJECTS_DIR := "res://data/objects/"
const DUNGEONS_DIR := "res://data/dungeons/"
const SPRITE_DIR := "res://assets/sprites/spirimonsters/"

const PO_EN := "res://translations/en.po"
const PO_FR := "res://translations/fr.po"

## Préfixes de clés adossées à une donnée : chacune doit avoir son .tres, et
## réciproquement. Les UI_* sont écrites à la main et hors périmètre.
const DATA_PREFIXES := ["SPECIES_", "ABILITY_", "TALENT_", "OBJECT_", "DUNGEON_"]

## Constantes de code contenant des slugs d'espèces mais dont le NOM ne le dit pas.
## Le balayage repère seul les constantes dont le nom contient « SPECIES » — d'où le nom
## de CELLE-CI, qui doit y échapper pour ne pas se vérifier elle-même. Les exceptions
## sont listées à la main plutôt que renommées : renommer du code de jeu pour arranger un
## test, c'est déguiser le test en refactor.
const EXTRA_SLUG_CONSTANTS := {
	"res://scripts/exploration/mechanisms/examinable_decor.gd": ["POOLS"],
}

var _fails: Array[String] = []

var _species: Dictionary = {}    ## id -> SpeciesData
var _abilities: Dictionary = {}  ## id -> AbilityData
var _talents: Dictionary = {}    ## id -> TalentData
var _objects: Dictionary = {}    ## id -> ObjectData
var _dungeons: Dictionary = {}   ## id -> DungeonConfig

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  OK   %s" % label)
	else:
		print("  FAIL %s" % label)
		_fails.append(label)

## Échec listant les fautifs, tronqué : trente slugs en vrac noient l'information utile.
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
	await get_tree().process_frame  # laisse les autoloads (GameData) charger
	_check_loading()
	_check_enums()
	_check_cross_refs()
	_check_code_species_refs()
	_check_translations()
	_check_sprites()
	print("")
	if _fails.is_empty():
		print("TOUT OK")
	else:
		print("ÉCHECS : %s" % [_fails])
	get_tree().quit(0 if _fails.is_empty() else 1)

# --------------------------------------------------------------------------
# Chargement : tout .tres se charge, se type, et son id colle à son nom de fichier
# --------------------------------------------------------------------------

func _check_loading() -> void:
	print("— chargement —")
	var unloadable: Array = []
	var untyped: Array = []
	var mismatched: Array = []
	var total := 0
	for dir_path in [SPECIES_DIR, ABILITIES_DIR, OBJECTS_DIR, DUNGEONS_DIR]:
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
				untyped.append("%s (id vide)" % file_name)
				continue
			# Le nom de fichier fait foi ailleurs dans le code (`data/species/%s.tres` %
			# slug, `assets/.../%s.png` % slug) : un id qui s'en écarte casse ces résolutions
			# sans rien signaler. Comparaison via key_token pour ne pas buter sur la forme
			# Unicode du nom de fichier (macOS écrit les accents en NFD, pas en NFC).
			if GameEnums.key_token(file_name.get_basename()) != GameEnums.key_token(res.id):
				mismatched.append("%s ≠ id '%s'" % [file_name, res.id])
				continue
			registry[res.id] = res
	_check(total > 0, "%d ressources trouvées dans data/" % total)
	_check_empty(unloadable, "toutes les ressources se chargent")
	_check_empty(untyped, "toutes les ressources ont un type et un id connus")
	_check_empty(mismatched, "l'id de chaque ressource correspond à son nom de fichier")
	print("  ·    %d espèces, %d capacités, %d talents, %d objets, %d donjons"
		% [_species.size(), _abilities.size(), _talents.size(), _objects.size(), _dungeons.size()])
	# GameData refait ce tri au boot avec sa propre logique de routage : un écart
	# signalerait que l'autoload ne voit pas les mêmes données que ce check.
	_check(GameData.all_species().size() == _species.size(),
		"GameData voit les mêmes espèces (%d)" % GameData.all_species().size())

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

## Registre correspondant au type d'une ressource, ou null si le type est inconnu.
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
	return null

# --------------------------------------------------------------------------
# Enums : les .tres stockent des entiers nus, une valeur hors plage passe inaperçue
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
			bad.append("%s.talker_chance = %.2f hors [0, 1]" % [id, sp.talker_chance])
	for id in _abilities:
		var ab: AbilityData = _abilities[id]
		_expect_enum(bad, id, "type", ab.type, GameEnums.AbilityType)
		_expect_enum(bad, id, "energy", ab.energy, GameEnums.Energy)
		_expect_enum(bad, id, "cost", ab.cost, GameEnums.Cost)
	for id in _objects:
		_expect_enum(bad, id, "effect", _objects[id].effect, GameEnums.ObjectEffect)
	_check_empty(bad, "toutes les valeurs d'enum sont dans leur plage")

func _expect_enum(bad: Array, id, field: String, value, enum_dict: Dictionary) -> void:
	if not enum_dict.values().has(int(value)):
		bad.append("%s.%s = %s" % [id, field, value])

# --------------------------------------------------------------------------
# Références croisées : un slug mort ne se voit qu'au moment où il est suivi
# --------------------------------------------------------------------------

func _check_cross_refs() -> void:
	print("— références —")
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
	_check_empty(dead, "aucune référence morte entre données")

	# Relation 1:1 talent ↔ espèce : chaque talent est porté, chaque porteur est reconnu.
	var unowned: Array = []
	for id in _talents:
		var owner: StringName = _talents[id].owner_species
		if owner == &"" or not _species.has(owner) or _species[owner].talent != id:
			unowned.append("%s (owner_species=%s)" % [id, owner])
	_check_empty(unowned, "chaque talent est porté par l'espèce qui le déclare")

# --------------------------------------------------------------------------
# Espèces citées par le CODE : un slug mort n'y déclenche rien du tout
# --------------------------------------------------------------------------

## Les mécanismes d'exploration codent en dur des listes d'espèces (quel spirimonstre une
## litière peut révéler, quel décor renvoie à qui). Un slug fautif y est INVISIBLE : la
## liste se contente de ne rien donner, sans erreur. Le contrôle des références entre
## `.tres` ne les voit pas — elles ne sont pas dans les données.
##
## On lit les constantes des scripts chargés plutôt que de parser du GDScript : la table
## de constantes est exacte là où une expression régulière serait approximative.
func _check_code_species_refs() -> void:
	print("— espèces citées par le code —")
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
	_check(checked > 0, "%d slugs d'espèce cités dans le code" % checked)
	_check_empty(dead, "toute espèce citée par le code existe dans data/species/")

## Slugs contenus dans une constante, qu'elle soit un tableau ou un dictionnaire de
## tableaux (les pools de décor sont indexés par type).
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
# Traductions : la clé manquante ne casse rien, elle affiche son propre nom
# --------------------------------------------------------------------------

func _check_translations() -> void:
	print("— traductions —")
	var en := _parse_po(PO_EN)
	var fr := _parse_po(PO_FR)
	_check(not en["keys"].is_empty() and not fr["keys"].is_empty(), "les deux .po se lisent")
	_check_empty(en["dupes"] + fr["dupes"], "aucun msgid en double")

	# Parité en/fr : une clé traduite d'un seul côté affiche son slug brut dans l'autre langue.
	var only_en: Array = []
	var only_fr: Array = []
	for k in en["keys"]:
		if not fr["keys"].has(k):
			only_en.append(k)
	for k in fr["keys"]:
		if not en["keys"].has(k):
			only_fr.append(k)
	_check_empty(only_en + only_fr, "en.po et fr.po portent les mêmes clés")

	# Chaque donnée a son nom traduit, dans les deux langues.
	var missing: Array = []
	for registry in [_species, _abilities, _talents, _objects, _dungeons]:
		for id in registry:
			var key: String = registry[id].name_key()
			for po in [["en", en], ["fr", fr]]:
				if not po[1]["keys"].has(key):
					missing.append("%s (%s)" % [key, po[0]])
	_check_empty(missing, "chaque donnée a son nom traduit en/fr")

	# Réciproque : une clé de donnée orpheline survit à la suppression de sa donnée et
	# reste invisible. Sans générateur idempotent pour réécrire les .po, c'est le seul
	# moyen de la voir.
	var expected := {}
	for registry in [_species, _abilities, _talents, _objects, _dungeons]:
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
	_check_empty(orphans, "aucune clé de donnée orpheline dans les .po")

	# Décomptes, pas des échecs : contenu à écrire, pas incohérence.
	print("  ·    %d clés en / %d fr ; %d msgstr vides en, %d fr"
		% [en["keys"].size(), fr["keys"].size(), en["empty"], fr["empty"]])

func _is_data_key(key: String) -> bool:
	for prefix in DATA_PREFIXES:
		if key.begins_with(prefix):
			return true
	return false

## Lecture minimale d'un .po : msgid/msgstr sur une ligne, ce qu'écrivent nos fichiers.
## Les continuations multi-lignes (en-tête) sont ignorées, sans incidence sur les clés.
func _parse_po(path: String) -> Dictionary:
	var out := {"keys": {}, "dupes": [], "empty": 0}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	var pending := ""
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line.begins_with("msgid \"") and line.ends_with("\""):
			var key := line.substr(7, line.length() - 8)
			if key == "":
				pending = ""  # en-tête du .po
				continue
			if out["keys"].has(key):
				out["dupes"].append(key)
			out["keys"][key] = ""
			pending = key
		elif line.begins_with("msgstr \"") and line.ends_with("\"") and pending != "":
			var value := line.substr(8, line.length() - 9)
			out["keys"][pending] = value
			if value == "":
				out["empty"] += 1
			pending = ""
	return out

# --------------------------------------------------------------------------
# Sprites : un chemin déclaré doit exister ; ne pas en déclarer est un manque d'art
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
	_check_empty(broken, "tout sprite déclaré existe sur le disque")
	print("  ·    %d espèces sans sprite déclaré (art à produire)" % without)
