## Vérification headless de la règle transverse « mécanisme épuisé » : ce avec quoi on ne peut
## plus interagir ne doit plus se présenter comme ACTIF — marqueur 3D grisé (ou retiré quand le
## mécanisme ne laisse rien derrière lui), `is_spent()` vrai (c'est ce que la mini-map lit pour
## éteindre la case), et retour à l'état actif au réarmement entre deux visites.
##
## Lancé par : Godot --headless --path . res://scenes/dev/spent_visuals_check.tscn
## (scène de démarrage, et non --script : voir geometry_check.gd.)
extends Node

const ScenarioCatalog := preload("res://scripts/dev/scenario_catalog.gd")
const EXPLORATION := preload("res://scenes/exploration/exploration.tscn")
const DungeonMechanism := preload("res://scripts/exploration/mechanisms/dungeon_mechanism.gd")

var _fails: Array[String] = []

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  OK   %s" % label)
	else:
		print("  FAIL %s" % label)
		_fails.append(label)

func _ready() -> void:
	_run_all()

func _run_all() -> void:
	await get_tree().process_frame
	await _check_grounds()
	await _check_crystal()
	await _check_trap()
	await _check_decor()
	print("")
	if _fails.is_empty():
		print("TOUT OK")
	else:
		print("ÉCHECS : %s" % [_fails])
	get_tree().quit(0 if _fails.is_empty() else 1)

# --------------------------------------------------------------------------
# Outils
# --------------------------------------------------------------------------

func _setup(scenario: StringName) -> Dictionary:
	ScenarioCatalog.selected_id = scenario
	var scene = EXPLORATION.instantiate()
	get_tree().root.add_child(scene)
	await get_tree().process_frame
	return {"scene": scene, "dm": scene.get_node("DungeonManager"), "player": scene.get_node("Player")}

func _teardown(ctx: Dictionary) -> void:
	ctx.scene.queue_free()
	await get_tree().process_frame

## Premier mécanisme d'une case exposant `prop` (chaque type a un état qui lui est propre).
func _mech_at(dm, cell: Vector3i, prop: String) -> Node:
	for m in dm.mechanisms_at(cell):
		if prop in m:
			return m
	return null

func _is_greyed(m: Node) -> bool:
	var marker: MeshInstance3D = m._marker
	if marker == null or marker.material_override == null:
		return false
	return marker.material_override.albedo_color.is_equal_approx(DungeonMechanism.SPENT_COLOR)

func _is_active_looking(m: Node) -> bool:
	return m._marker != null and not _is_greyed(m)

# --------------------------------------------------------------------------
# Sols spéciaux : sol friable creusé (grisé, réarmé entre visites) et litière recyclée
# (marqueur RETIRÉ : la case est redevenue un sol ordinaire)
# --------------------------------------------------------------------------

func _check_grounds() -> void:
	print("[sol friable creusé · litière recyclée]")
	var ctx := await _setup(&"grounds")
	var ground := _mech_at(ctx.dm, Vector3i(1, 0, 1), "info_chance")
	var litter := _mech_at(ctx.dm, Vector3i(1, 0, 3), "loot_max")
	_check(ground != null and litter != null, "sol friable et litière en place")
	_check(_is_active_looking(ground) and not ground.is_spent(), "avant : le sol friable a l'air actif")
	ctx.player.teleport_to(Vector3i(1, 0, 1))
	ground.dig(ctx.player)
	_check(ground.is_spent(), "creusé : is_spent() (la carte éteint la case, cf. doc « an icon is shown »)")
	_check(_is_greyed(ground), "creusé : marqueur grisé")
	ground.reset_between_visits()
	_check(not ground.is_spent() and _is_active_looking(ground),
			"visite suivante : de nouveau creusable ET de nouveau coloré")

	_check(_is_active_looking(litter) and not litter.is_spent(), "avant : la litière a l'air active")
	litter.recycle(ctx.player)
	_check(litter.is_spent(), "recyclée : is_spent()")
	_check(litter._marker == null, "recyclée : marqueur RETIRÉ (la case est un sol normal)")
	_check(not litter.blocks_walk(), "recyclée : on marche dessus (cohérent avec le visuel)")
	await _teardown(ctx)

# --------------------------------------------------------------------------
# Cristal de rafraîchissement : grisé mais NON aplati (il reste un obstacle)
# --------------------------------------------------------------------------

func _check_crystal() -> void:
	print("[cristal de rafraîchissement utilisé]")
	var ctx := await _setup(&"chests")
	var crystal := _mech_at(ctx.dm, Vector3i(0, 0, 2), "_used")
	_check(crystal != null and _is_active_looking(crystal), "avant : le cristal a l'air actif")
	crystal.refresh()
	_check(crystal.is_spent(), "utilisé : is_spent()")
	_check(_is_greyed(crystal), "utilisé : marqueur grisé")
	_check(is_equal_approx(crystal._marker.scale.y, 1.0),
			"utilisé : PAS aplati (c'est toujours un obstacle infranchissable)")
	_check(crystal.blocks_walk(), "utilisé : bloque toujours le passage")
	crystal.reset_between_visits()
	_check(not crystal.is_spent() and _is_active_looking(crystal), "visite suivante : cristal réarmé")
	await _teardown(ctx)

# --------------------------------------------------------------------------
# Piège : déjà conforme avant cette passe — on verrouille le comportement
# --------------------------------------------------------------------------

func _check_trap() -> void:
	print("[piège déclenché]")
	var ctx := await _setup(&"traps")
	var trap := _mech_at(ctx.dm, Vector3i(1, 0, 2), "kind")
	_check(trap != null and not trap.is_spent(), "avant : piège armé")
	trap.reactivates = true
	trap.on_enter(ctx.player)
	_check(trap.is_spent(), "déclenché : is_spent()")
	_check(_is_greyed(trap), "déclenché : marqueur grisé")
	trap.reset_between_visits()
	_check(not trap.is_spent() and _is_active_looking(trap),
			"version réarmable : de nouveau armé ET de nouveau coloré")
	await _teardown(ctx)

# --------------------------------------------------------------------------
# Décor examinable : grisé, sans aplatissement (élément mural)
# --------------------------------------------------------------------------

func _check_decor() -> void:
	print("[décor examiné]")
	var ctx := await _setup(&"walls")
	var decor := _mech_at(ctx.dm, Vector3i(0, 0, 1), "decor_type")
	_check(decor != null and _is_active_looking(decor), "avant : le décor a l'air actif")
	decor.examine(ctx.player)
	_check(decor.is_spent(), "examiné : is_spent()")
	_check(_is_greyed(decor), "examiné : marqueur grisé")
	_check(is_equal_approx(decor._marker.scale.y, 1.0), "examiné : PAS aplati (élément mural)")
	await _teardown(ctx)
