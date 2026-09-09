## Vérification headless des coffres contre la doc Notion (Level Design / Mechanisms
## « Chest », plus les clauses « coffre » des talents Reveal Traps et Trick to Reveal).
## Éprouve le butin, le piège déguisé, le choix offert par Reveal Traps et le fait qu'un
## rival ne consomme pas un coffre à butin, dans le vrai scénario « chests ».
##
## Lancé par : Godot --headless --path . res://scenes/dev/chest_check.tscn
## (scène de démarrage, et non --script : voir geometry_check.gd.)
extends Node

const ScenarioCatalog := preload("res://scripts/dev/scenario_catalog.gd")
const EXPLORATION := preload("res://scenes/exploration/exploration.tscn")
const RIVAL_SCENE := preload("res://scenes/exploration/rival/rival.tscn")
const DungeonMechanism := preload("res://scripts/exploration/mechanisms/dungeon_mechanism.gd")

## Cases des deux coffres du scénario « chests ».
const LOOT_CELL := Vector3i(1, 0, 1)
const TRAP_CELL := Vector3i(1, 0, 3)

## Espèce coéquipière SANS le talent reveal_traps (érzélak porte trick_to_reveal).
const NO_TALENT_TEAMMATE := &"érzélak"
## Espèce coéquipière AVEC le talent reveal_traps.
const REVEAL_TRAPS_TEAMMATE := &"razél"

var _fails: Array[String] = []
var _messages: Array[String] = []

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
	await _check_loot_chest()
	await _check_rival_on_loot_chest()
	await _check_trap_chest()
	await _check_reveal_traps_declined()
	await _check_reveal_traps_accepted()
	print("")
	if _fails.is_empty():
		print("TOUT OK")
	else:
		print("ÉCHECS : %s" % [_fails])
	get_tree().quit(0 if _fails.is_empty() else 1)

# --------------------------------------------------------------------------
# Terrain de test
# --------------------------------------------------------------------------

## Monte le scénario « chests » et retourne {scene, dm, player, loot, trap}.
## `teammate` fixe le talent du duo (le coffre lit GameSession à l'ouverture).
func _setup(teammate: StringName) -> Dictionary:
	ScenarioCatalog.selected_id = &"chests"
	var scene = EXPLORATION.instantiate()
	get_tree().root.add_child(scene)
	await get_tree().process_frame
	var dm = scene.get_node("DungeonManager")
	var player = scene.get_node("Player")
	GameSession.teammate = teammate
	GameSession.inventory.clear()
	_messages.clear()
	dm.message_posted.connect(func(text: String) -> void: _messages.append(text))
	return {
		"scene": scene, "dm": dm, "player": player,
		"loot": _chest_at(dm, LOOT_CELL), "trap": _chest_at(dm, TRAP_CELL),
	}

func _teardown(ctx: Dictionary) -> void:
	ctx.scene.queue_free()
	await get_tree().process_frame

## Coffre posé sur une case (ou null).
func _chest_at(dm, cell: Vector3i) -> Node:
	for m in dm.mechanisms_at(cell):
		if "is_trap" in m:
			return m
	return null

func _inventory_total() -> int:
	var total := 0
	for count in GameSession.inventory.values():
		total += count
	return total

## Le marqueur du mécanisme est-il grisé (mécanisme épuisé) ?
func _is_greyed(mechanism: Node) -> bool:
	var marker: MeshInstance3D = mechanism._marker
	if marker == null or marker.material_override == null:
		return false
	return marker.material_override.albedo_color.is_equal_approx(DungeonMechanism.SPENT_COLOR)

func _action_ids(dm, cell: Vector3i, who: Node) -> Array:
	var ids := []
	for a in dm.actions_for(cell, Vector3i(0, 0, 1), who):
		ids.append(a.id)
	return ids

# --------------------------------------------------------------------------
# Coffre à butin (doc : « will give objects if the player steps on them »)
# --------------------------------------------------------------------------

func _check_loot_chest() -> void:
	print("[coffre à butin]")
	var ctx := await _setup(REVEAL_TRAPS_TEAMMATE)
	var chest = ctx.loot
	_check(chest != null and not chest.is_trap, "un coffre à butin sur %s" % LOOT_CELL)
	_check(not chest.is_opened() and not chest.revealed, "au départ : ni ouvert ni révélé")
	chest.reveal()
	_check(chest.revealed and not chest.is_opened(),
			"reveal() révèle sans ouvrir (talent Trick to Reveal)")
	ctx.player.teleport_to(LOOT_CELL)
	chest.on_enter(ctx.player)
	var got := _inventory_total()
	_check(chest.is_opened(), "marcher dessus l'ouvre")
	_check(got >= chest.loot_min and got <= chest.loot_max,
			"butin dans [%d, %d] (reçu %d)" % [chest.loot_min, chest.loot_max, got])
	_check(_messages.size() == 1, "le butin est annoncé : « %s »" % ["".join(_messages)])
	_check(_is_greyed(chest), "un coffre vidé est grisé (plus actionnable, donc plus « actif »)")
	chest.on_enter(ctx.player)
	_check(_inventory_total() == got, "un coffre ne se rouvre pas (ouvert une seule fois)")
	await _teardown(ctx)

# --------------------------------------------------------------------------
# Un rival qui passe sur un coffre à butin ne le consomme pas (il n'a pas d'inventaire)
# --------------------------------------------------------------------------

func _check_rival_on_loot_chest() -> void:
	print("[rival sur un coffre à butin]")
	var ctx := await _setup(REVEAL_TRAPS_TEAMMATE)
	var chest = ctx.loot
	var rival = RIVAL_SCENE.instantiate()
	rival.species_id = &"kalilk"
	rival.position = ctx.dm.cell_to_world(LOOT_CELL)
	ctx.dm.add_child(rival)
	await get_tree().process_frame
	chest.on_enter(rival)
	_check(not chest.is_opened(), "le coffre reste fermé")
	_check(_inventory_total() == 0, "aucun objet versé à l'inventaire du joueur")
	ctx.player.teleport_to(LOOT_CELL)
	chest.on_enter(ctx.player)
	_check(chest.is_opened() and _inventory_total() > 0, "le butin attendait bien le joueur")
	await _teardown(ctx)

# --------------------------------------------------------------------------
# Coffre piégé sans le talent (doc : « some are actually teleportation traps in disguise »)
# --------------------------------------------------------------------------

func _check_trap_chest() -> void:
	print("[coffre piégé, duo sans Reveal Traps]")
	var ctx := await _setup(NO_TALENT_TEAMMATE)
	var chest = ctx.trap
	_check(chest != null and chest.is_trap, "un coffre piégé sur %s" % TRAP_CELL)
	ctx.player.teleport_to(TRAP_CELL)
	ctx.player.set_invisible(5)  # fog mantel en cours : le piège doit le rompre
	chest.on_enter(ctx.player)
	_check(not chest.is_pending(), "aucun choix offert sans le talent")
	_check(chest.is_opened(), "le coffre est consommé")
	_check(ctx.player.cell != TRAP_CELL, "le joueur est téléporté (%s)" % [ctx.player.cell])
	_check(_inventory_total() == 0, "aucun butin (piège pur)")
	_check(_is_greyed(chest), "un coffre piégé déclenché est grisé")
	_check(not ctx.player.is_hidden_from_rivals(), "le piège rompt l'invisibilité (fog mantel)")
	await _teardown(ctx)

# --------------------------------------------------------------------------
# Coffre piégé avec Reveal Traps (doc : « they can decide to teleport or not. The chest
# gives 1 or more object no matter what, but more if players choose to teleport. »)
# --------------------------------------------------------------------------

func _check_reveal_traps_declined() -> void:
	print("[coffre piégé + Reveal Traps : refus]")
	var ctx := await _setup(REVEAL_TRAPS_TEAMMATE)
	var chest = ctx.trap
	_check(GameSession.party_has_talent(&"reveal_traps"), "le duo porte bien reveal_traps")
	ctx.player.teleport_to(TRAP_CELL)
	chest.on_enter(ctx.player)
	_check(chest.is_pending() and not chest.is_opened(), "le coffre attend le choix du joueur")
	_check(ctx.player.cell == TRAP_CELL, "personne n'est téléporté tant que rien n'est choisi")
	var ids := _action_ids(ctx.dm, TRAP_CELL, ctx.player)
	_check(&"chest_teleport" in ids and &"chest_decline" in ids,
			"les deux actions sont proposées (%s)" % [ids])
	chest.decline_teleport(ctx.player)
	_check(chest.is_opened() and not chest.is_pending(), "le coffre est consommé après le choix")
	_check(ctx.player.cell == TRAP_CELL, "refus : le joueur reste sur place")
	_check(_inventory_total() == chest.trap_loot_declined,
			"refus : %d objet(s) quand même" % chest.trap_loot_declined)
	_check(ctx.dm.actions_for(TRAP_CELL, Vector3i(0, 0, 1), ctx.player).is_empty(),
			"plus aucune action sur la case")
	await _teardown(ctx)

func _check_reveal_traps_accepted() -> void:
	print("[coffre piégé + Reveal Traps : acceptation]")
	var ctx := await _setup(REVEAL_TRAPS_TEAMMATE)
	var chest = ctx.trap
	ctx.player.teleport_to(TRAP_CELL)
	chest.on_enter(ctx.player)
	chest.accept_teleport(ctx.player)
	_check(ctx.player.cell != TRAP_CELL, "acceptation : le joueur est téléporté (%s)" % [ctx.player.cell])
	_check(_inventory_total() == chest.trap_loot_accepted,
			"acceptation : %d objets" % chest.trap_loot_accepted)
	_check(chest.trap_loot_accepted > chest.trap_loot_declined,
			"la doc impose davantage de butin en acceptant")
	await _teardown(ctx)
