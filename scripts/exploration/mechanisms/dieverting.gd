## Dieverting (FR « cubimprévu »).
##
## Doc Notion (Level Design / Mechanisms « Dieverting »). Dé impatient qui s'active dès
## qu'il rencontre le joueur. Si le joueur possède un objet capable de le détruire (pelle ou
## pierre runique), on lui offre le CHOIX de le détruire ou de subir ; sinon il subit
## aussitôt. Le dé lancé donne l'une de 6 issues. Traité comme un mécanisme (et non un objet)
## : ne se stocke pas dans l'inventaire.
##
## Le choix détruire/subir est offert par le menu d'actions contextuelles du HUD (comme
## ouvrir une porte verrouillée) : tant que le joueur n'a pas tranché, le dé reste EN ATTENTE
## sur sa case et repropose ses deux actions à chaque passage.
##
## Le dé est un VRAI d6 (faces opposées = 7) : chacune des 6 issues de la doc est une face,
## le cube culbute pour de bon et s'arrête sur celle qui est sortie, puis le résultat est
## annoncé au joueur par le bandeau de messages du HUD ([method DungeonManager.post_message]).
##
## Deux points que la doc ne tranche pas, arbitrés ici :
##  - un dé qui a roulé (ou qui a été détruit) est consommé : il ne se réarme pas, ni dans la
##    visite ni entre deux visites ;
##  - les magnitudes X / Y / Z (objets perdus, ETH, DEN) sont des placeholders exportés.
##
## Pas de `class_name` : `extends` par chemin. Référence l'autoload GameSession.
extends "res://scripts/exploration/mechanisms/dungeon_mechanism.gd"

const ExplorationAction := preload("res://scripts/exploration/exploration_action.gd")
const ChestScript := preload("res://scripts/exploration/mechanisms/chest.gd")
const RIVAL_SCENE := preload("res://scenes/exploration/rival/rival.tscn")

## Les 6 issues du dé (doc).
enum Outcome {
	TELEPORT_ENTRANCE_LOSE_OBJECTS,  ## → entrée, perd des objets (placés dans un coffre)
	TELEPORT_ENTRANCE_LOSE_ETH,  ## → entrée, chaque perso perd de l'ETH
	SPAWN_RIVALS,  ## jusqu'à 3 groupes de rivaux apparaissent
	TELEPORT_EXIT_LOSE_OBJECTS_DEN,  ## → sortie, perd des objets + chaque perso perd du DEN
	DESTROY_OBJECTS,  ## détruit jusqu'à 3 objets au hasard
	ADD_OBJECTS,  ## ajoute jusqu'à 3 objets au hasard
}

## Objets capables de détruire un dieverting.
const DESTROYERS: Array[StringName] = [&"spade", &"rune_stone"]

## Objets pouvant être ajoutés (issue ADD_OBJECTS) — placeholder.
@export var add_pool: Array[StringName] = [&"rune_stone", &"tea_drop", &"smoke_bomb", &"spade"]

# Magnitudes placeholder (doc : X / Y / Z à définir).
@export var objects_lost := 2
@export var eth_lost_each := 10
@export var den_lost_each := 15
@export var max_objects_delta := 3

## Issue SPAWN_RIVALS : jusqu'à 3 GROUPES de rivaux (une silhouette sur la carte = un groupe),
## dans un rayon de `rival_spawn_radius` cases autour du joueur.
## ## TODO: doc « specifics TBD » — le nombre, la distance et surtout les espèces devront venir
## du level design (DungeonConfig.possible_species) quand les donjons seront authorés ; le pool
## ci-dessous est un placeholder de test.
@export var rival_spawn_max := 3
@export var rival_spawn_radius := 4
@export var rival_pool: Array[StringName] = [&"ravbak", &"kalilk"]

# --- Dé (visuel) ---

## Arête du cube, en mètres.
const DIE_SIZE := 0.45
## Côté d'un point (pip), son épaisseur en saillie de la face, et l'écart entre deux points.
const PIP_SIZE := 0.075
const PIP_DEPTH := 0.012
const PIP_SPACING := DIE_SIZE * 0.26

## Normale LOCALE de chaque face, faces opposées sommant à 7 (comme un vrai dé).
const FACE_NORMALS := {
	1: Vector3.UP,
	6: Vector3.DOWN,
	2: Vector3.BACK,
	5: Vector3.FORWARD,
	3: Vector3.RIGHT,
	4: Vector3.LEFT,
}

## Disposition des points d'une face, en unités de [constant PIP_SPACING].
const PIP_LAYOUTS := {
	1: [Vector2(0, 0)],
	2: [Vector2(-1, -1), Vector2(1, 1)],
	3: [Vector2(-1, -1), Vector2(0, 0), Vector2(1, 1)],
	4: [Vector2(-1, -1), Vector2(-1, 1), Vector2(1, -1), Vector2(1, 1)],
	5: [Vector2(-1, -1), Vector2(-1, 1), Vector2(0, 0), Vector2(1, -1), Vector2(1, 1)],
	6:
	[Vector2(-1, -1), Vector2(-1, 0), Vector2(-1, 1), Vector2(1, -1), Vector2(1, 0), Vector2(1, 1)],
}

## Durée de la culbute (s). 0 = pas d'animation (vérifications headless).
@export var roll_duration := 0.9
## Temps pendant lequel le dé reste lisible, en l'air, avant de retomber sur sa case.
@export var roll_hold := 0.7

## Distance devant le joueur et hauteur auxquelles le dé culbute. Le joueur se tient sur la
## MÊME case que le dé : posé au sol, un cube de 45 cm serait sous la caméra (yeux à
## [constant DungeonManager.EYE_HEIGHT]) — donc invisible. Il saute donc dans le champ de
## vision, un peu au-delà de la case voisine : plus près, il mange tout l'écran.
## ## TODO: en cul-de-sac, le dé en l'air empiète sur le mur d'en face (cosmétique, à revoir
## avec les vrais visuels).
const AIR_DISTANCE := 1.45
const AIR_HEIGHT := 0.45  # centre du cube ≈ hauteur des yeux : le dé est pile dans l'axe

## Clé de message par issue (affichée par le HUD via [signal DungeonManager.message_posted]).
const MESSAGE_KEYS := {
	Outcome.TELEPORT_ENTRANCE_LOSE_OBJECTS: "UI_DIEVERTING_ENTRANCE_OBJECTS",
	Outcome.TELEPORT_ENTRANCE_LOSE_ETH: "UI_DIEVERTING_ENTRANCE_ETH",
	Outcome.SPAWN_RIVALS: "UI_DIEVERTING_RIVALS",
	Outcome.TELEPORT_EXIT_LOSE_OBJECTS_DEN: "UI_DIEVERTING_EXIT_OBJECTS_DEN",
	Outcome.DESTROY_OBJECTS: "UI_DIEVERTING_DESTROY_OBJECTS",
	Outcome.ADD_OBJECTS: "UI_DIEVERTING_ADD_OBJECTS",
}

var _active := true
## Le dé a rencontré le joueur, qui a de quoi le détruire : choix en attente sur la case.
var _pending := false

# État de la culbute en cours (lu par [method _roll_step], pilotée par un tween).
var _roll_axis := Vector3.UP
var _roll_turns := 2.0
var _roll_final := Quaternion.IDENTITY


func is_active() -> bool:
	return _active


## Un dé qui a roulé (ou qui a été détruit) est épuisé (règle transverse).
func is_spent() -> bool:
	return not _active


## Un choix détruire/subir est-il en attente sur cette case ?
func is_pending() -> bool:
	return _pending


## Le joueur peut-il détruire ce dieverting (possède pelle ou pierre runique) ?
func is_destroyable_by(who: Node) -> bool:
	if _dungeon != null and not _dungeon.is_player(who):
		return false
	for obj in DESTROYERS:
		if GameSession.has_object(obj):
			return true
	return false


## Rencontre du dé : s'il n'est pas destructible par le joueur, il se déclenche aussitôt
## (« impatient »). S'il l'est, le choix passe par le menu d'actions.
func on_enter(who: Node) -> void:
	if not _active:
		return
	if _dungeon != null and not _dungeon.is_player(who):
		return
	if is_destroyable_by(who):
		_pending = true
		return
	submit(who)


## Actions proposées tant que le choix est en attente : détruire (contre un objet) ou subir.
func on_tile_actions(who: Node) -> Array:
	if not _active or not _pending:
		return []
	var actions: Array = []
	if is_destroyable_by(who):
		actions.append(
			ExplorationAction.new(
				&"destroy_dieverting",
				"UI_ACTION_DESTROY_DIEVERTING",
				Callable(self, "destroy").bind(who)
			)
		)
	actions.append(
		ExplorationAction.new(
			&"submit_dieverting", "UI_ACTION_SUBMIT_DIEVERTING", Callable(self, "submit").bind(who)
		)
	)
	return actions


## Détruit le dieverting en consommant un objet destructeur (pelle en priorité). Retourne
## true si détruit.
func destroy(_who: Node) -> bool:
	if not _active:
		return false
	for obj in DESTROYERS:
		if GameSession.has_object(obj):
			GameSession.consume_object(obj)
			_deactivate()
			_post_message("UI_DIEVERTING_DESTROYED", [])
			return true
	return false


## Subit le dé : le lance (ou `forced` pour les tests), le fait rouler devant le joueur,
## annonce le résultat, puis applique l'issue. À AWAITER si l'on veut voir les effets appliqués
## (l'issue n'est appliquée qu'une fois le dé retombé) ; `roll_duration = 0` court-circuite
## l'animation. Retourne l'issue tirée.
func submit(who: Node, forced: int = -1) -> int:
	if not _active:
		return -1
	var outcome := forced if forced >= 0 else randi() % Outcome.size()
	# Désarmé AVANT le roulement : le dé a joué, même si l'animation dure encore. (L'issue,
	# elle, peut poser un coffre sur la case, faire apparaître des rivaux ou téléporter le
	# joueur : elle n'est appliquée qu'à la retombée.)
	_active = false
	_pending = false
	var locked: bool = "input_locked" in who
	if locked:
		who.input_locked = true  # on ne s'en va pas au milieu d'un jet
	await _play_roll(outcome + 1, who)  # face 1..6 = les 6 issues, dans l'ordre de la doc
	_post_message("UI_DIEVERTING_ROLL", [outcome + 1, tr(MESSAGE_KEYS[outcome])])
	await _settle_back()
	_mark_rolled()
	if locked and is_instance_valid(who):
		who.input_locked = false
	_apply(outcome, who)
	return outcome


func _apply(outcome: int, who: Node) -> void:
	match outcome:
		Outcome.TELEPORT_ENTRANCE_LOSE_OBJECTS:
			_teleport_to_entrance(who)
			_drop_chest(_lose_objects(objects_lost))
		Outcome.TELEPORT_ENTRANCE_LOSE_ETH:
			_teleport_to_entrance(who)
			_drain_party_eth(eth_lost_each)
		Outcome.SPAWN_RIVALS:
			_spawn_rival_groups(who)
		Outcome.TELEPORT_EXIT_LOSE_OBJECTS_DEN:
			_teleport_to_exit(who)
			_drop_chest(_lose_objects(objects_lost))
			_damage_party_den(den_lost_each)
		Outcome.DESTROY_OBJECTS:
			_lose_objects(randi_range(1, max_objects_delta))  # « up to 3 »
		Outcome.ADD_OBJECTS:
			_add_objects(max_objects_delta)


## Renvoi à l'ENTRÉE du donjon. Repli (aucune entrée déclarée, ex. scénario de dev) : une
## case au hasard, comme un piège de téléportation.
func _teleport_to_entrance(who: Node) -> void:
	if _dungeon == null:
		return
	if _dungeon.has_entrance():
		_dungeon.teleport_actor_to(who, _dungeon.entrance_cell())
	else:
		_dungeon.teleport_actor(who)


## Renvoi à une SORTIE du donjon, tirée au hasard s'il y en a plusieurs (doc). L'entrée
## compte parmi les sorties (cf. [method DungeonManager.set_entrance]).
func _teleport_to_exit(who: Node) -> void:
	if _dungeon == null:
		return
	if _dungeon.has_exit():
		_dungeon.teleport_actor_to(who, _dungeon.random_exit())
	else:
		_dungeon.teleport_actor(who)


## Retire `count` objets au hasard de l'inventaire et retourne la liste de ce qui a été perdu
## (pour le coffre). Un objet possédé en plusieurs exemplaires peut sortir plusieurs fois.
func _lose_objects(count: int) -> Array[StringName]:
	var lost: Array[StringName] = []
	for i in range(count):
		var owned: Array = GameSession.inventory.keys()
		if owned.is_empty():
			break
		var object_id: StringName = owned[randi() % owned.size()]
		GameSession.remove_object(object_id, 1)
		lost.append(object_id)
	return lost


## Dépose les objets perdus dans un coffre posé LÀ OÙ ÉTAIT le dieverting (doc). Le dé, lui,
## est désormais inerte : les deux mécanismes cohabitent sur la case.
func _drop_chest(lost: Array[StringName]) -> void:
	if lost.is_empty() or _dungeon == null:
		return
	var chest = ChestScript.new()
	chest.fixed_loot = lost
	chest.position = _dungeon.cell_to_world(cell)
	_dungeon.add_child(chest)


func _add_objects(max_count: int) -> void:
	var n := randi_range(1, max_count)
	for i in range(n):
		if not add_pool.is_empty():
			GameSession.add_object(add_pool[randi() % add_pool.size()], 1)


## Fait apparaître 1 à [member rival_spawn_max] groupes de rivaux près du joueur.
func _spawn_rival_groups(who: Node) -> void:
	if _dungeon == null or rival_pool.is_empty():
		return
	var origin: Vector3i = who.cell if "cell" in who else cell
	var spots: Array[Vector3i] = _dungeon.free_cells_near(origin, rival_spawn_radius)
	var n: int = mini(randi_range(1, rival_spawn_max), spots.size())
	for i in range(n):
		var rival = RIVAL_SCENE.instantiate()
		rival.species_id = rival_pool[randi() % rival_pool.size()]
		rival.position = _dungeon.cell_to_world(spots[i])
		_dungeon.add_child(rival)


func _drain_party_eth(amount: int) -> void:
	GameSession.spend_eth(GameSession.PartySlot.MAIN, amount)
	GameSession.spend_eth(GameSession.PartySlot.TEAMMATE, amount)


func _damage_party_den(amount: int) -> void:
	GameSession.apply_den_damage(GameSession.PartySlot.MAIN, amount)
	GameSession.apply_den_damage(GameSession.PartySlot.TEAMMATE, amount)
	GameSession.resolve_party_wipe()


func _deactivate() -> void:
	_active = false
	_pending = false
	_mark_spent()


## Un dé consommé (roulé ou détruit) ne revient pas d'une visite à l'autre.
func reset_between_visits() -> void:
	pass


## Poste un message de feedback au joueur (le HUD l'affiche). `args` alimente le format.
func _post_message(key: String, args: Array) -> void:
	if _dungeon == null:
		return
	var text := tr(key)
	if not args.is_empty():
		text = text % args
	_dungeon.post_message(text)


# --------------------------------------------------------------------------
# Le dé : visuel et roulement
# --------------------------------------------------------------------------


func _spawn_visual() -> void:
	var mesh := _add_marker(Color(0.9, 0.35, 0.1), DIE_SIZE, DIE_SIZE)  # cube orange
	# Le dé s'éclaire lui-même : la face qu'on doit LIRE est celle tournée vers le joueur,
	# donc souvent celle qui est dans l'ombre du donjon.
	var mat := mesh.material_override as StandardMaterial3D
	if mat != null:
		mat.emission_enabled = true
		mat.emission = Color(0.9, 0.35, 0.1)
		mat.emission_energy_multiplier = 0.45
	_add_pips()


## Points des 6 faces, plaqués juste au-dessus de chaque face du cube. Enfants du marqueur :
## ils culbutent avec lui.
func _add_pips() -> void:
	if _marker == null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.09, 0.07)
	var half := DIE_SIZE * 0.5
	for value in FACE_NORMALS:
		var n: Vector3 = FACE_NORMALS[value]
		# Deux axes du PLAN de la face (n'importe lesquels : un dé n'a pas de haut).
		var u := n.cross(Vector3.UP)
		if u.length_squared() < 0.01:
			u = n.cross(Vector3.BACK)
		u = u.normalized()
		var w := n.cross(u).normalized()
		# Pastille plate (mince dans l'axe de la face) plutôt qu'un cube en saillie.
		var size: Vector3 = (u.abs() + w.abs()) * PIP_SIZE + n.abs() * PIP_DEPTH
		for offset in PIP_LAYOUTS[value]:
			var pip := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = size
			pip.mesh = box
			pip.material_override = mat
			pip.position = (
				n * (half + PIP_DEPTH * 0.5)
				+ u * (offset.x * PIP_SPACING)
				+ w * (offset.y * PIP_SPACING)
			)
			_marker.add_child(pip)


## Culbute : le dé saute dans le champ de vision du joueur, tourne en décélérant et s'arrête
## sur `face`, tournée vers lui. Retourne quand le dé est immobile (à awaiter).
func _play_roll(face: int, who: Node) -> void:
	if roll_duration <= 0.0 or _marker == null:
		if _marker != null:
			_marker.basis = _basis_for_face(face, -_facing_of(who))
		return
	var facing := _facing_of(who)
	var air: Vector3 = _rest_position() + facing * AIR_DISTANCE + Vector3(0.0, AIR_HEIGHT, 0.0)
	# Axe de culbute quelconque (un dé lancé ne tourne pas autour d'un axe choisi) et 2 à 3
	# tours : assez pour lire le mouvement, pas assez pour brouiller la face finale.
	_roll_axis = (
		Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
	)
	_roll_turns = randf_range(2.0, 3.0)
	_roll_final = Quaternion(_basis_for_face(face, -facing).orthonormalized())
	var tween := create_tween()
	tween.tween_method(_roll_step, 0.0, 1.0, roll_duration)
	(
		tween
		. parallel()
		. tween_property(_marker, "position", air, roll_duration * 0.45)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	await tween.finished


## Un pas de culbute : rotation qui décélère, raccordée sur l'orientation finale à la fin.
func _roll_step(t: float) -> void:
	if not is_instance_valid(_marker):
		return
	var eased := 1.0 - pow(1.0 - t, 3.0)
	var tumble := Quaternion(_roll_axis, _roll_turns * TAU * eased)
	var blend := clampf((t - 0.6) / 0.4, 0.0, 1.0)
	_marker.basis = Basis(tumble.slerp(_roll_final, blend))


## Le dé reste lisible en l'air le temps qu'on lise le message, puis retombe sur sa case.
func _settle_back() -> void:
	if _marker == null or roll_duration <= 0.0:
		return
	var tween := create_tween()
	tween.tween_interval(roll_hold)
	(
		tween
		. tween_property(_marker, "position", _rest_position(), 0.3)
		. set_trans(Tween.TRANS_BOUNCE)
		. set_ease(Tween.EASE_OUT)
	)
	await tween.finished


## Position de repos du marqueur : posé au centre de sa case (cf. `_add_marker_box`).
func _rest_position() -> Vector3:
	return Vector3(0.0, DIE_SIZE * 0.5, 0.0)


## Orientation qui amène la face `value` sur la direction `toward` (LOCALE). Le roulis autour
## de cet axe est un quart de tour tiré au hasard (deux jets ne se ressemblent pas) plus un
## léger travers : un dé posé de guingois, pas un losange en équilibre sur la pointe.
func _basis_for_face(value: int, toward: Vector3) -> Basis:
	var n: Vector3 = FACE_NORMALS[value]
	var axis := toward.normalized()
	var roll := (randi() % 4) * PI * 0.5 + randf_range(-0.22, 0.22)
	return Basis(Quaternion(axis, roll) * Quaternion(n, axis))


## Direction « devant le joueur », exprimée dans le repère LOCAL du mécanisme.
func _facing_of(who: Node) -> Vector3:
	var dir := Vector3.BACK
	if who != null and who.has_method("facing_delta"):
		var fd: Vector3i = who.facing_delta()
		if fd != Vector3i.ZERO:
			dir = Vector3(fd.x, 0.0, fd.z).normalized()
	return (global_transform.basis.inverse() * dir).normalized()


## Un dé qui a roulé n'est plus actionnable : il se GRISE comme tout mécanisme épuisé
## ([constant SPENT_COLOR]), au lieu de garder sa teinte vive de dé actif. Il garde en
## revanche sa forme (pas de [method _mark_spent], qui aplatirait le cube) : la face sortie
## reste tournée vers le joueur, seule trace durable de ce qui s'est joué sur cette case.
func _mark_rolled() -> void:
	if _marker == null:
		return
	_grey_marker()
	# Les points sont presque noirs : lisibles sur l'orange vif, plus du tout sur le gris
	# sombre. On les éclaircit pour que la face reste déchiffrable une fois le dé éteint.
	var pip_mat := StandardMaterial3D.new()
	pip_mat.albedo_color = Color(0.86, 0.86, 0.88)
	for pip in _marker.get_children():
		if pip is MeshInstance3D:
			pip.material_override = pip_mat
