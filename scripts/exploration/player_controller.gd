## Déplacement du joueur sur la grille du donjon (3D, 1re personne).
##
## Déplacement orthogonal case-par-case relatif à l'orientation, transitions lissées,
## rotation par pas de 90°. Interroge le [DungeonManager] (groupe "dungeon") pour la
## praticabilité et l'occupation ; déclenche une rencontre en entrant sur la case d'un
## rival. Un pas réussi fait avancer le tour ([method DungeonManager.advance_turn]).
class_name PlayerController
extends Node3D

const AfflictionState := preload("res://scripts/exploration/mechanisms/affliction_state.gd")

@export var move_duration := 0.18
## Vitesse de rattrapage du corps vers l'angle visé (deg/s). Élevé = le regard libre suit la
## souris de près et les rotations 90° restent lisses (modèle porté du proto Unity).
@export var yaw_follow_speed := 720.0

var cell: Vector3i
var _dungeon: DungeonManager
var _busy := false
## Angle de lacet VISUEL visé, en degrés (base rigide + regard libre) — le corps le rejoint.
var _target_yaw_deg := 0.0
## Angle de lacet de DÉPLACEMENT, en degrés (toujours un multiple de 90°). Découplé du visuel :
## garantit des pas orthogonaux (jamais de diagonale, même en regardant à 45°). Une orientation
## n'est « validée » pour le déplacement qu'une fois la rotation de 90° accomplie.
var _move_yaw_deg := 0.0

## Verrou de déplacement : quand actif, le joueur ignore ses entrées de déplacement/rotation
## (utilisé par le test d'équilibre du pont étroit, qui pilote la position directement).
var input_locked := false

## Effets persistants subis par le joueur (poison, disarray). Lu en duck-typing par les
## pièges via la propriété `affliction`.
var affliction := AfflictionState.new()

## Invisibilité (fog mantel) : cases restantes pendant lesquelles les rivaux ne voient pas le
## joueur. Annulée par une rencontre OU l'activation d'un piège.
var invisible_moves := 0
## Non-poursuite (torment veil / costume) : cases restantes pendant lesquelles les rivaux ne
## poursuivent pas. Annulée par une rencontre (mais PAS par un piège).
var unpursued_moves := 0
## Espèce dont le joueur a l'apparence (costume), le cas échéant.
var disguise_species := &""

func _ready() -> void:
	_dungeon = get_tree().get_first_node_in_group("dungeon") as DungeonManager
	if _dungeon == null:
		push_error("[PlayerController] aucun DungeonManager dans le groupe 'dungeon'.")
		return
	cell = _dungeon.world_to_cell(global_position)
	global_position = _dungeon.cell_to_world(cell)
	_dungeon.register_player(self)
	add_to_group("player")  # repéré par le HUD pour les actions contextuelles

	# L'orientation (yaw) est pilotée par PlayerInputHandler (base rigide + regard libre à la
	# souris, modèle Unity) ; le corps rejoint l'angle visé en continu dans _process.
	_target_yaw_deg = rad_to_deg(rotation.y)

## Vrai si aucun déplacement/rotation en cours (autorise une nouvelle action).
func is_at_rest() -> bool:
	return not _busy

## Direction actuellement regardée, en delta de case (x, 0, z) — pour interroger les actions
## contextuelles de la case regardée. Basée sur l'orientation de DÉPLACEMENT (cardinale), pas
## sur le regard libre : on interagit avec la case qu'on a orthogonalement en face.
func facing_delta() -> Vector3i:
	var world := Basis(Vector3.UP, deg_to_rad(_move_yaw_deg)) * Vector3.FORWARD
	return Vector3i(roundi(world.x), 0, roundi(world.z))

func _process(delta: float) -> void:
	# Le corps rejoint en continu l'angle visé (regard libre + rotations 90°), par le chemin
	# le plus court.
	var target := deg_to_rad(_target_yaw_deg)
	var step := deg_to_rad(yaw_follow_speed) * delta
	rotation.y += clampf(angle_difference(rotation.y, target), -step, step)

## Fixe l'angle de lacet VISUEL visé (degrés), posé par [PlayerInputHandler].
func set_yaw_target(deg: float) -> void:
	_target_yaw_deg = deg

## Fixe l'angle de lacet de DÉPLACEMENT (degrés, multiple de 90°), posé par [PlayerInputHandler]
## une fois une rotation de 90° accomplie.
func set_move_yaw(deg: float) -> void:
	_move_yaw_deg = deg

## Angle de lacet visé courant (degrés) — lu par [PlayerInputHandler] pour s'initialiser.
func current_yaw_deg() -> float:
	return _target_yaw_deg

## Oriente immédiatement le joueur (corps + cible visuelle + déplacement) — au placement.
func set_start_yaw(rad: float) -> void:
	rotation.y = rad
	_target_yaw_deg = rad_to_deg(rad)
	_move_yaw_deg = rad_to_deg(rad)

## Une rotation vient d'être effectuée (au clavier, ou par dérive du regard libre au-delà de
## [member PlayerInputHandler.commit_angle]) :
## fait avancer le tour, comme un pas.
func rotated_90() -> void:
	if _dungeon != null:
		_dungeon.advance_turn()

## Tente un pas dans une direction LOCALE (Vector3.FORWARD/BACK/LEFT/RIGHT).
func try_move(local_dir: Vector3) -> void:
	if _busy or _dungeon == null or input_locked:
		return
	# Disarray : une part des mouvements est déviée vers une AUTRE translation (doc).
	if affliction.consume_move():
		local_dir = _random_translation_except(local_dir)
	# Direction basée sur l'orientation de DÉPLACEMENT cardinale (multiple de 90°) : garantit
	# un pas orthogonal, jamais une diagonale, même si le regard est à 45°.
	var world := Basis(Vector3.UP, deg_to_rad(_move_yaw_deg)) * local_dir
	var delta := Vector3i(roundi(world.x), 0, roundi(world.z))
	if delta == Vector3i.ZERO:
		return
	var target := cell + delta

	# Porte fermée sur l'arête franchie : rien ne passe (ni escalier, ni chute, ni rencontre).
	if _dungeon.is_edge_blocked(cell, target):
		return

	# Escalier devant (modèle proto Unity) : on est porté 2 cases plus loin + changement
	# d'étage. Ne se prend QUE dans l'axe de l'escalier (`face_dir`) — pas en perpendiculaire,
	# où il bloque comme un mur.
	var stairs := _stairs_at(target)
	if stairs != null:
		if delta == stairs.face_dir:
			var dest: Vector3i = stairs.stairs_destination(cell, delta)
			if _dungeon.is_floor(dest):
				await _climb_step(dest)
		return  # (mauvaise direction : bloqué)

	if _dungeon.is_blocked_by_mechanism(target):
		return  # mécanisme infranchissable (gate fermée…)
	if not _dungeon.is_floor(target):
		# Pas de sol ici : chute s'il y a un sol à un niveau inférieur (bord de vide), sinon mur.
		var landing := _dungeon.fall_landing(target)
		if landing == target:
			# Rien en dessous : c'est un mur — sauf trou franc laissé par le level design, où
			# la chute est sans fond, donc fatale.
			if _dungeon.is_bottomless(target):
				await fall_forever(target)
			return
		await fall_to(landing, target.y - landing.y)
		return
	var occ := _dungeon.occupant_at(target)
	if occ != null:
		_dungeon.request_encounter(occ, false)  # rencontre : pas de déplacement
		return

	cell = target
	_busy = true
	var tween := create_tween()
	tween.tween_property(self, "global_position", _dungeon.cell_to_world(target), move_duration)
	await tween.finished
	_busy = false
	# Un pas consomme les états de discrétion (invisibilité / non-poursuite).
	_tick_hidden_on_move()
	# Mécanismes de la case atteinte (pièges…), puis avance du tour.
	_dungeon.notify_entered(cell, self)
	_dungeon.advance_turn()

## Chute vers `landing` (case de sol en contrebas) : descente animée, dégâts ∝ nombre de
## niveaux, puis résolution normale (mécanismes de la case + avance de tour).
##
## Public : le pilote du pont étroit ([code]exploration.gd[/code]) s'en sert pour qu'une chute
## de pont soit exactement une chute normale (même profondeur, mêmes dégâts, même tour).
func fall_to(landing: Vector3i, levels: int) -> void:
	_dungeon.notify_level_change(self, cell, landing)  # les rivaux témoins peuvent suivre
	cell = landing
	_busy = true
	var tween := create_tween()
	tween.tween_property(self, "global_position", _dungeon.cell_to_world(landing), 0.35)
	await tween.finished
	_busy = false
	var dmg := DungeonManager.fall_damage(levels)
	GameSession.apply_den_damage(GameSession.PartySlot.MAIN, dmg)
	GameSession.apply_den_damage(GameSession.PartySlot.TEAMMATE, dmg)
	GameSession.resolve_party_wipe()
	_tick_hidden_on_move()
	_dungeon.notify_entered(cell, self)
	_dungeon.advance_turn()

## Chute SANS FOND (trou franc du level design) : le duo tombe hors du donjon et est dévitalisé
## — un sol qu'on n'atteint jamais est un sol trop bas pour qu'on y survive. On ne bloque pas
## silencieusement le pas : le donjon est en faute, ça doit se voir en jouant.
##
## ## TODO(dungeon checker): un trou sans fond est toujours une erreur d'auteur. À détecter au
## chargement du donjon plutôt qu'en le subissant, quand un validateur de donjon existera.
func fall_forever(into: Vector3i) -> void:
	input_locked = true
	_busy = true
	push_warning("[PlayerController] chute sans fond en %s : le level design a laissé un trou sans sol." % into)
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(self, "global_position",
			_dungeon.cell_to_world(into) - Vector3(0.0, 6.0, 0.0), 0.8)
	await tween.finished
	_busy = false
	GameSession.set_den(GameSession.PartySlot.MAIN, 0)
	GameSession.set_den(GameSession.PartySlot.TEAMMATE, 0)
	GameSession.resolve_party_wipe()  # dévitalisation : sortie du donjon
	input_locked = false

## Une direction de translation locale au hasard, différente de `dir` (déviation disarray).
func _random_translation_except(dir: Vector3) -> Vector3:
	var dirs := [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]
	dirs.erase(dir)
	return dirs[randi() % dirs.size()]

## Relocalisation instantanée sur une case (piège de téléportation). L'occupation est gérée
## par [method DungeonManager.teleport_actor] ; le joueur, lui, n'occupe pas de case.
func teleport_to(to_cell: Vector3i) -> void:
	cell = to_cell
	global_position = _dungeon.cell_to_world(to_cell)

## Escalier présent sur la case `c` (mécanisme exposant `stairs_destination`), ou null.
func _stairs_at(c: Vector3i) -> Node:
	for m in _dungeon.mechanisms_at(c):
		if m.has_method("stairs_destination"):
			return m
	return null

## Franchit un escalier : montée/descente LISSE vers `dest` (autre étage, 2 cases plus loin),
## puis résolution normale (mécanismes de la case + avance de tour).
func _climb_step(dest: Vector3i) -> void:
	if dest.y != cell.y:
		_dungeon.notify_level_change(self, cell, dest)  # les rivaux témoins peuvent suivre
	cell = dest
	_busy = true
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "global_position", _dungeon.cell_to_world(dest), 0.4)
	await tween.finished
	_busy = false
	_tick_hidden_on_move()
	_dungeon.notify_entered(cell, self)
	_dungeon.advance_turn()

# --------------------------------------------------------------------------
# Discrétion (invisibilité / non-poursuite) — capacités & objets d'exploration
# --------------------------------------------------------------------------

## Rend invisible des rivaux pour `tiles` déplacements (fog mantel). Prend le maximum.
func set_invisible(tiles: int) -> void:
	invisible_moves = maxi(invisible_moves, tiles)

## Empêche la poursuite pour `moves` déplacements (torment veil / costume).
func set_unpursued(moves: int, species: StringName = &"") -> void:
	unpursued_moves = maxi(unpursued_moves, moves)
	if species != &"":
		disguise_species = species

## Le joueur est-il indétectable par les rivaux (invisible ou non-poursuivi) ?
func is_hidden_from_rivals() -> bool:
	return invisible_moves > 0 or unpursued_moves > 0

## Annule uniquement l'invisibilité (règle fog mantel : rompue par piège/rencontre).
func clear_invisibility() -> void:
	invisible_moves = 0

## Annule toute discrétion (à l'entrée d'une rencontre).
func clear_hidden() -> void:
	invisible_moves = 0
	unpursued_moves = 0
	disguise_species = &""

## Décompte les états de discrétion d'un déplacement.
func _tick_hidden_on_move() -> void:
	if invisible_moves > 0:
		invisible_moves -= 1
	if unpursued_moves > 0:
		unpursued_moves -= 1
		if unpursued_moves == 0:
			disguise_species = &""

## Fin de tour : applique les afflictions persistantes. Le poison retire du DEN aux DEUX
## personnages du duo (le joueur sur la carte = le duo), et déclenche la sortie de donjon
## si le duo est entièrement dévitalisé.
func on_turn_elapsed() -> void:
	var dmg := affliction.tick_poison()
	if dmg > 0:
		GameSession.apply_den_damage(GameSession.PartySlot.MAIN, dmg)
		GameSession.apply_den_damage(GameSession.PartySlot.TEAMMATE, dmg)
		GameSession.resolve_party_wipe()
