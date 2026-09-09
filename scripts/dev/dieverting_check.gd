## Vérification headless du dieverting (« cubimprévu ») contre la doc Notion
## (Level Design / Mechanisms). Éprouve le choix détruire/subir et les 6 issues du dé, une
## par une (issue forcée), dans le vrai scénario « chests » — donc avec une entrée, une
## sortie, un joueur et un donjon réels.
##
## Lancé par : Godot --headless --path . res://scenes/dev/dieverting_check.tscn
## (scène de démarrage, et non --script : voir geometry_check.gd.)
extends Node

const ScenarioCatalog := preload("res://scripts/dev/scenario_catalog.gd")
const EXPLORATION := preload("res://scenes/exploration/exploration.tscn")
const Dieverting := preload("res://scripts/exploration/mechanisms/dieverting.gd")
const DungeonMechanism := preload("res://scripts/exploration/mechanisms/dungeon_mechanism.gd")

## Case du premier dé dans le scénario « chests ».
const DIE_CELL := Vector3i(1, 0, 5)

var _fails: Array[String] = []
## Derniers messages postés par le donjon (bandeau de feedback du HUD).
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
	await _check_choice()
	await _check_auto_submit()
	await _check_roll_animation()
	for outcome in Dieverting.Outcome.values():
		await _check_outcome(outcome)
	print("")
	if _fails.is_empty():
		print("TOUT OK")
	else:
		print("ÉCHECS : %s" % [_fails])
	get_tree().quit(0 if _fails.is_empty() else 1)

# --------------------------------------------------------------------------
# Terrain de test
# --------------------------------------------------------------------------

## Monte le scénario « chests », pose le joueur sur la case du dé et retourne
## {scene, dm, player, die}.
func _setup() -> Dictionary:
	ScenarioCatalog.selected_id = &"chests"
	var scene = EXPLORATION.instantiate()
	get_tree().root.add_child(scene)
	await get_tree().process_frame
	var dm = scene.get_node("DungeonManager")
	var player = scene.get_node("Player")
	_messages.clear()
	dm.message_posted.connect(func(text: String) -> void: _messages.append(text))
	var die = null
	for m in dm.mechanisms_at(DIE_CELL):
		if m.has_method("submit"):
			die = m
	if die != null:
		die.roll_duration = 0.0  # culbute court-circuitée : les tests logiques restent instantanés
	player.teleport_to(DIE_CELL)
	return {"scene": scene, "dm": dm, "player": player, "die": die}

func _teardown(ctx: Dictionary) -> void:
	ctx.scene.queue_free()
	await get_tree().process_frame

func _inventory_total() -> int:
	var total := 0
	for count in GameSession.inventory.values():
		total += count
	return total

## Coffre posé sur la case du dé (ou null) : un mécanisme à contenu imposé.
func _chest_at_die(dm) -> Node:
	for m in dm.mechanisms_at(DIE_CELL):
		if "fixed_loot" in m and not m.fixed_loot.is_empty():
			return m
	return null

# --------------------------------------------------------------------------
# Choix détruire / subir (doc : offert si le joueur a une pelle ou une pierre runique)
# --------------------------------------------------------------------------

func _check_choice() -> void:
	print("[choix détruire/subir]")
	var ctx := await _setup()
	var die = ctx.die
	_check(die != null, "un dieverting sur %s" % DIE_CELL)
	GameSession.inventory.clear()
	GameSession.add_object(&"spade", 1)
	die.on_enter(ctx.player)
	_check(die.is_active() and die.is_pending(), "avec une pelle : le dé attend le choix (pas de roulement)")
	var actions: Array = ctx.dm.actions_for(DIE_CELL, Vector3i(0, 0, 1), ctx.player)
	var ids := []
	for a in actions:
		ids.append(a.id)
	_check(&"destroy_dieverting" in ids and &"submit_dieverting" in ids,
			"les deux actions sont proposées (%s)" % [ids])
	_check(die.destroy(ctx.player), "détruire consomme un objet destructeur")
	_check(not GameSession.has_object(&"spade"), "la pelle est dépensée")
	_check(not die.is_active() and not die.is_pending(), "le dé détruit est inerte")
	_check(_messages.size() == 1, "la destruction est annoncée : « %s »" % ["".join(_messages)])
	_check(ctx.dm.actions_for(DIE_CELL, Vector3i(0, 0, 1), ctx.player).is_empty(),
			"plus aucune action sur la case")
	await _teardown(ctx)

func _check_auto_submit() -> void:
	print("[sans objet destructeur : le dé s'active seul]")
	var ctx := await _setup()
	GameSession.inventory.clear()
	ctx.die.on_enter(ctx.player)
	_check(not ctx.die.is_active(), "le dé a roulé de lui-même")
	_check(not ctx.die.is_pending(), "aucun choix laissé en attente")
	await _teardown(ctx)

## La culbute pour de vrai (durée nominale) : le dé sort de sa case de repos, verrouille les
## commandes le temps du jet, s'arrête sur la face sortie et la présente au joueur.
func _check_roll_animation() -> void:
	print("[culbute du dé]")
	var ctx := await _setup()
	var die = ctx.die
	var player = ctx.player
	GameSession.inventory.clear()
	die.roll_duration = 0.25
	die.roll_hold = 0.1
	var marker: MeshInstance3D = die._marker
	_check(marker != null, "le dé a un visuel")
	var pips := marker.get_child_count() if marker != null else 0
	_check(pips == 21, "%d points sur les 6 faces (1+2+3+4+5+6)" % pips)
	var rest: Vector3 = marker.position
	var face := Dieverting.Outcome.ADD_OBJECTS + 1  # issue inoffensive : rien ne bouge autour
	die.submit(player, Dieverting.Outcome.ADD_OBJECTS)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(player.input_locked, "les commandes sont verrouillées pendant le jet")
	_check(marker.position != rest, "le dé quitte le sol pour culbuter dans le champ de vision")
	await get_tree().create_timer(1.2).timeout
	_check(not player.input_locked, "les commandes sont rendues à la retombée")
	_check(marker.position.is_equal_approx(rest), "le dé est retombé sur sa case")
	# La face sortie est celle qui regarde le joueur (le joueur regarde +z, donc la face
	# pointe vers -z une fois le dé retombé).
	var toward_player: Vector3 = -Vector3(player.facing_delta().x, 0.0, player.facing_delta().z)
	var normal: Vector3 = marker.basis * Dieverting.FACE_NORMALS[face]
	_check(normal.normalized().dot(toward_player.normalized()) > 0.95,
			"la face %d est tournée vers le joueur (produit scalaire %.2f)"
			% [face, normal.normalized().dot(toward_player.normalized())])
	await _teardown(ctx)

# --------------------------------------------------------------------------
# Les 6 issues
# --------------------------------------------------------------------------

func _check_outcome(outcome: int) -> void:
	var ctx := await _setup()
	var dm = ctx.dm
	var player = ctx.player
	var die = ctx.die
	GameSession.inventory.clear()
	GameSession.add_object(&"tea_drop", 2)
	GameSession.add_object(&"smoke_bomb", 2)
	var before_objects := _inventory_total()
	var before_eth: int = GameSession.get_eth(GameSession.PartySlot.MAIN)
	var before_den: int = GameSession.get_den(GameSession.PartySlot.MAIN)
	var before_rivals: int = dm.rivals().size()

	match outcome:
		Dieverting.Outcome.TELEPORT_ENTRANCE_LOSE_OBJECTS:
			print("[1. renvoi à l'entrée + perte d'objets]")
			await die.submit(player, outcome)
			_check(player.cell == dm.entrance_cell(),
					"le joueur est à l'entrée %s (%s)" % [dm.entrance_cell(), player.cell])
			_check(_inventory_total() == before_objects - die.objects_lost,
					"%d objets perdus" % die.objects_lost)
			var chest := _chest_at_die(dm)
			_check(chest != null, "un coffre est posé là où était le dé")
			if chest != null:
				_check(chest.fixed_loot.size() == die.objects_lost,
						"le coffre contient exactement les objets perdus (%s)" % [chest.fixed_loot])
				chest.on_enter(player)
				_check(_inventory_total() == before_objects, "les rouvrir rend le compte exact")
		Dieverting.Outcome.TELEPORT_ENTRANCE_LOSE_ETH:
			print("[2. renvoi à l'entrée + perte d'ETH]")
			await die.submit(player, outcome)
			_check(player.cell == dm.entrance_cell(), "le joueur est à l'entrée (%s)" % player.cell)
			_check(GameSession.get_eth(GameSession.PartySlot.MAIN) == before_eth - die.eth_lost_each
					and GameSession.get_eth(GameSession.PartySlot.TEAMMATE) == before_eth - die.eth_lost_each,
					"les DEUX personnages perdent %d ETH" % die.eth_lost_each)
			_check(_inventory_total() == before_objects, "aucun objet perdu")
		Dieverting.Outcome.SPAWN_RIVALS:
			print("[3. apparition de groupes rivaux]")
			await die.submit(player, outcome)
			await get_tree().process_frame  # _ready des rivaux (enregistrement auprès du donjon)
			var spawned: int = dm.rivals().size() - before_rivals
			_check(spawned >= 1 and spawned <= die.rival_spawn_max,
					"%d groupe(s) apparu(s) (1 à %d)" % [spawned, die.rival_spawn_max])
			var far := true
			for rival in dm.rivals():
				var d: Vector3i = rival.cell - player.cell
				if absi(d.x) + absi(d.z) > die.rival_spawn_radius or rival.cell == player.cell:
					far = false
			_check(far, "tous apparaissent à proximité (≤ %d cases)" % die.rival_spawn_radius)
			_check(player.cell == DIE_CELL, "le joueur n'est pas déplacé")
		Dieverting.Outcome.TELEPORT_EXIT_LOSE_OBJECTS_DEN:
			print("[4. renvoi à une sortie + perte d'objets + perte de DEN]")
			await die.submit(player, outcome)
			_check(player.cell in dm.exit_cells(),
					"le joueur est sur une sortie %s (%s)" % [dm.exit_cells(), player.cell])
			_check(_inventory_total() == before_objects - die.objects_lost,
					"%d objets perdus" % die.objects_lost)
			_check(_chest_at_die(dm) != null, "un coffre est posé là où était le dé")
			_check(GameSession.get_den(GameSession.PartySlot.MAIN) == before_den - die.den_lost_each
					and GameSession.get_den(GameSession.PartySlot.TEAMMATE) == before_den - die.den_lost_each,
					"les DEUX personnages perdent %d DEN" % die.den_lost_each)
		Dieverting.Outcome.DESTROY_OBJECTS:
			print("[5. destruction d'objets]")
			await die.submit(player, outcome)
			var lost := before_objects - _inventory_total()
			_check(lost >= 1 and lost <= die.max_objects_delta,
					"%d objet(s) détruit(s) (jusqu'à %d)" % [lost, die.max_objects_delta])
			_check(_chest_at_die(dm) == null, "détruits, donc AUCUN coffre (contrairement aux issues 1 et 4)")
			_check(player.cell == DIE_CELL, "le joueur n'est pas déplacé")
		Dieverting.Outcome.ADD_OBJECTS:
			print("[6. gain d'objets]")
			await die.submit(player, outcome)
			var gained := _inventory_total() - before_objects
			_check(gained >= 1 and gained <= die.max_objects_delta,
					"%d objet(s) gagné(s) (jusqu'à %d)" % [gained, die.max_objects_delta])
			_check(player.cell == DIE_CELL, "le joueur n'est pas déplacé")

	_check(not die.is_active(), "le dé est consommé après avoir roulé")
	_check(die._marker.material_override.albedo_color.is_equal_approx(DungeonMechanism.SPENT_COLOR),
			"le dé qui a roulé est grisé (plus actionnable, donc plus « actif »)")
	_check(is_equal_approx(die._marker.scale.y, 1.0),
			"…mais garde sa forme : la face sortie reste lisible")
	# Le PREMIER message est l'annonce du jet. L'issue 1 en ajoute un second : le test y
	# rouvre le coffre déposé, qui annonce son butin (cf. chest.gd).
	_check(not _messages.is_empty() and _messages[0].contains(str(outcome + 1)),
			"le résultat est annoncé au joueur : « %s »" % [_messages[0] if not _messages.is_empty() else ""])
	await _teardown(ctx)
