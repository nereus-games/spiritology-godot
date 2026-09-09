## Racine de la scène d'exploration (3D, persistante).
##
## Relie la demande de rencontre du [DungeonManager] à l'ouverture d'une rencontre en
## OVERLAY additif via [TransitionManager] (exploration mise en pause, visible derrière).
## En cas de victoire, le rival est retiré du donjon (dissous).
extends Node3D

const ScenarioCatalog := preload("res://scripts/dev/scenario_catalog.gd")

@onready var _dungeon: DungeonManager = $DungeonManager

var _pending_rival: Node

# --- Pilote temps réel du pont étroit (par case, dans les deux sens) ---
var _active_bridge  ## case de pont en cours, ou null
var _bridge_dir: Vector3i  ## sens d'avancée (case)
var _bridge_from: Vector3i  ## case de départ de l'avancée en cours
var _bridge_balance  ## modèle d'équilibre de la traversée, porté de case en case
var _in_bridge := false  ## une traversée est en cours
## Roulis caméra maximal (deg) au déséquilibre extrême — simule la perte d'équilibre.
const BRIDGE_ROLL_DEG := 28.0


func _ready() -> void:
	_dungeon.encounter_requested.connect(_on_encounter_requested)
	_dungeon.bridge_collision.connect(_on_bridge_collision)
	_dungeon.turn_advanced.connect(_on_turn_advanced)
	TransitionManager.encounter_finished.connect(_on_encounter_finished)
	GameSession.party_wiped.connect(_on_party_wiped)
	# Entrée de donjon : l'ETH du duo est entièrement restauré (règle « Game Units »), et le
	# suivi des capacités d'exploration (usage unique/visite) repart à zéro.
	GameSession.restore_party_eth()
	GameSession.reset_exploration_abilities()
	# DEV : construit le scénario de test choisi (peuple la grille + la session) et place le
	# joueur. Fait EN DERNIER pour que l'état posé par le scénario (objets, capacités marquées)
	# ne soit pas écrasé par la logique d'entrée de donjon ci-dessus.
	var start: Vector3i = ScenarioCatalog.build(ScenarioCatalog.selected_id, _dungeon)
	# DEV : le joueur démarre là où il entrerait dans le donjon — c'est donc l'entrée (qui,
	# règle doc, compte aussi comme sortie). Les mécanismes qui y renvoient (dieverting) ont
	# ainsi une vraie destination, au lieu d'un repli aléatoire.
	_dungeon.set_entrance(start)
	_dungeon.render_grid()  # génère sol + murs visibles depuis la grille logique
	var player := get_node_or_null("Player")
	if player != null and player.has_method("teleport_to"):
		player.teleport_to(start)
		# Les scénarios s'étendent vers +z ; le joueur regarde par défaut vers -z (le mur
		# derrière lui). On l'oriente vers le donjon (corps + cible de lacet).
		if player.has_method("set_start_yaw"):
			player.set_start_yaw(PI)


func _on_encounter_requested(rival: Node, initiated_by_rival: bool) -> void:
	if _pending_rival != null:
		return
	_pending_rival = rival
	# Une rencontre rompt toute discrétion du joueur (fog mantel, torment veil, costume).
	var pl := get_tree().get_first_node_in_group("player")
	if pl != null and pl.has_method("clear_hidden"):
		pl.clear_hidden()
	var rival_id: StringName = rival.species_id if "species_id" in rival else &"ravbak"
	# État de carte du rival : son DEN maximal est un réglage de LEVEL DESIGN, et les dégâts
	# encaissés en exploration (chute) sont reportés dans la rencontre. Dictionnaire vide = pas
	# de suivi sur la carte, le fighter part sur ses valeurs par défaut.
	var rival_state := {}
	if "den" in rival and "max_den" in rival:
		rival_state = {"den": rival.den, "max_den": rival.max_den}
	print(
		(
			"[Exploration] Rencontre avec '%s' (rival init=%s, état carte=%s)."
			% [rival_id, initiated_by_rival, rival_state]
		)
	)
	TransitionManager.open_encounter(_player_duo(), [rival_id], {}, [rival_state])


func _on_encounter_finished(result: StringName) -> void:
	print("[Exploration] Rencontre terminée : %s." % result)
	# Compteur FDE : tous les rivaux dévitalisés == &"victory" (défaite/timeout/fuite : non).
	GameSession.register_encounter_end(result == &"victory")
	if result == &"victory" and is_instance_valid(_pending_rival):
		_pending_rival.queue_free()  # rival dissous
	_pending_rival = null
	# Duo entièrement dévitalisé : restaure le DEN à 1 chacun et émet party_wiped
	# (déclenche _on_party_wiped pour sortir le duo du donjon).
	GameSession.resolve_party_wipe()


## Le duo a été entièrement dévitalisé : le DEN est déjà restauré à 1 chacun par
## [GameSession] ; l'exploration doit sortir le duo du donjon courant.
func _on_party_wiped() -> void:
	print("[Exploration] Duo dévitalisé : sortie du donjon.")
	## TODO: ramener le duo hors du donjon (retour carte du monde / entrée du donjon)
	## quand la navigation inter-scènes sera en place.


func _on_turn_advanced(_turn: int) -> void:
	pass  # hook tours (PSY, IFP, etc.)


# --------------------------------------------------------------------------
# Pilote temps réel du pont étroit (test d'équilibre)
# --------------------------------------------------------------------------


func _process(delta: float) -> void:
	_drive_bridge(delta)


func _drive_bridge(delta: float) -> void:
	var player := get_node_or_null("Player")
	if player == null:
		return
	# Détection d'une case de pont engagée (entrée sur une planche).
	if _active_bridge == null:
		for m in _dungeon.get_children():
			if m.has_method("is_engaged") and m.is_engaged():
				_begin_bridge_cell(m, player)
				break
		return
	# Entrée latérale : INVERSÉE pour CORRIGER (pousser du bon côté rétablit l'équilibre).
	var input := -Input.get_axis("move_left", "move_right")
	var state: StringName = _active_bridge.advance(delta, input)
	var bal = _active_bridge.balance()
	# Avancée le long de la case (from -> from+dir) ; le déséquilibre = ROULIS de la caméra.
	var t := clampf(bal.progress, 0.0, 1.0)
	var from_w := _dungeon.cell_to_world(_bridge_from)
	var to_w := _dungeon.cell_to_world(_bridge_from + _bridge_dir)
	player.global_position = from_w.lerp(to_w, t)
	_set_camera_roll(player, bal.imbalance)
	_hud_show_balance(bal.imbalance)
	if state == &"complete":
		_advance_bridge_cell(player)
	elif state == &"fell":
		_fall_off_bridge(player)


## Début d'une avancée sur une case de pont (dans le sens du regard). Si une traversée est
## déjà en cours, la case REPREND le test d'équilibre courant (déséquilibre ET vitesse
## latérale conservés) au lieu d'en démarrer un neuf.
func _begin_bridge_cell(bridge, player) -> void:
	_active_bridge = bridge
	_bridge_dir = bridge.direction()
	_bridge_from = bridge.cell
	if _in_bridge and _bridge_balance != null:
		bridge.adopt_balance(_bridge_balance)
	else:
		_in_bridge = true
		_bridge_balance = bridge.balance()
	player.input_locked = true
	_hud_show_balance(_bridge_balance.imbalance)


## Case franchie : passe à la suivante ; enchaîne s'il y a encore du pont, sinon fin.
##
## Doc : « turns here are not defined by player interaction, but by bridge length » — chaque
## case de pont franchie coûte donc un tour, exactement comme un pas normal.
func _advance_bridge_cell(player) -> void:
	var dest: Vector3i = _bridge_from + _bridge_dir
	_bridge_balance = _active_bridge.balance()  # porté à la case suivante
	_active_bridge = null
	# Une case de pont franchie EST un mouvement : elle décompte le disarray, comme un pas.
	# (La déviation elle-même n'a pas de sens ici — on n'a pas le choix de la direction sur
	# une planche ; sur le pont, le disarray s'exprime par l'inertie de commande.) Vaut pour
	# TOUTES les issues ci-dessous : la case est franchie, qu'on y trouve quelqu'un ou non.
	var aff = player.get("affliction")
	if aff != null:
		aff.consume_move()
	# Quelqu'un occupe déjà la case d'arrivée. Symétrique du cas où c'est le rival qui vient
	# vers nous ([method RivalBehavior.take_turn]) : sur une planche les deux tombent, sur du
	# sol solide c'est un contact normal.
	var occupant := _dungeon.occupant_at(dest)
	if occupant != null:
		if _dungeon.is_narrow_bridge(dest):
			_on_bridge_collision(occupant, dest)
		else:
			_finish_bridge(player)
			player.teleport_to(dest)
			# Sortir du pont EST un déplacement : ça coûte un tour, comme n'importe quel pas
			# (contrairement à un contact sur place, où le joueur ne bouge pas). Le tour s'écoule
			# AVANT la rencontre — même ordre que la collision sur planche, où c'est la chute qui
			# le fait avancer.
			_dungeon.advance_turn()
			# Le rival a pu bouger (ou être dissous) pendant ce tour : pas de rencontre avec
			# quelqu'un qui n'est plus là.
			if is_instance_valid(occupant) and _dungeon.occupant_at(dest) == occupant:
				_dungeon.request_encounter(occupant, false)
		return
	player.teleport_to(dest)
	_dungeon.notify_entered(dest, player)  # engage la case suivante si c'est encore du pont
	var still := false
	for m in _dungeon.mechanisms_at(dest):
		if m.has_method("is_engaged") and m.is_engaged():
			still = true
	if not still:
		_finish_bridge(player)  # arrivé sur du sol solide
	_dungeon.advance_turn()


## Chute du pont : le personnage tombe sur le SOL en contrebas (à la profondeur qu'a voulue
## le level design) et subit les dégâts de chute NORMAUX, comme un pas dans le vide.
func _fall_off_bridge(player) -> void:
	# On tombe de la case dont on est le plus proche : celle visée si l'on a passé la moitié
	# du segment ET que le vide s'ouvre bien dessous (sinon on surplombe déjà le sol solide).
	var from_cell := _bridge_from
	var ahead: Vector3i = _bridge_from + _bridge_dir
	if (
		_active_bridge != null
		and _active_bridge.balance().progress >= 0.5
		and _dungeon.fall_landing(ahead) != ahead
	):
		from_cell = ahead
	_finish_bridge(player)
	var landing := _dungeon.fall_landing(from_cell)
	if landing == from_cell:
		# Rien en dessous : le pont n'enjambe aucun vide (level design incomplet). On se
		# rattrape sur la planche plutôt que de disparaître.
		## TODO(dungeon checker): la doc impose qu'un pont étroit surplombe TOUJOURS un sol, et
		## qu'une remontée existe avant le pont (sauf si la chute dévitalise). Rien ne le vérifie
		## sur un vrai donjon — seul le scénario de dev est contrôlé (`geometry_check`). À reprendre
		## quand un validateur de donjon sera écrit ; en attendant, ce garde-fou d'exécution.
		push_warning("[Exploration] Chute du pont en %s : aucun sol en contrebas." % from_cell)
		player.teleport_to(from_cell)
		return
	player.teleport_to(from_cell)
	# (Les rivaux témoins sont prévenus par `fall_to` → `DungeonManager.notify_level_change`.)
	await player.fall_to(landing, from_cell.y - landing.y)


## Un rival arrive sur la planche où se trouve le joueur : les deux tombent, atterrissent sur
## la MÊME case, et la rencontre s'engage là (doc). Le rival peut être dévitalisé par la
## chute — dans ce cas il n'y a pas de rencontre du tout.
func _on_bridge_collision(rival, tile: Vector3i) -> void:
	var player := get_node_or_null("Player")
	if player == null or not is_instance_valid(rival):
		return
	var landing := _dungeon.fall_landing(tile)
	if landing == tile:
		return  # aucun vide sous cette planche : personne ne tombe
	var levels := tile.y - landing.y
	_finish_bridge(player)  # la traversée est interrompue
	player.teleport_to(tile)
	# Le joueur n'occupe pas de case : le rival peut atterrir exactement sur la sienne.
	var rival_alive: bool = rival.drop_to(landing, levels)
	await player.fall_to(landing, levels)
	if rival_alive and is_instance_valid(rival):
		_dungeon.request_encounter(rival, true)


func _finish_bridge(player) -> void:
	_active_bridge = null
	_in_bridge = false
	_bridge_balance = null
	player.input_locked = false
	_set_camera_roll(player, 0.0)
	_hud_hide_balance()


## Roulis de perte d'équilibre : appliqué au JOUEUR (pivot à l'origine ≈ pieds/sol), pas au
## rig caméra (qui pivoterait au niveau des yeux).
func _set_camera_roll(player, imbalance: float) -> void:
	player.rotation.z = deg_to_rad(imbalance * BRIDGE_ROLL_DEG)


func _hud_show_balance(imbalance: float) -> void:
	var hud := get_node_or_null("HudExploration")
	if hud != null and hud.has_method("show_balance"):
		hud.show_balance(imbalance)


func _hud_hide_balance() -> void:
	var hud := get_node_or_null("HudExploration")
	if hud != null and hud.has_method("hide_balance"):
		hud.hide_balance()


## Duo jouable depuis la session, avec repli de démo si la partie n'est pas initialisée.
func _player_duo() -> Array:
	var ids: Array = []
	if GameSession.main_character != &"":
		ids.append(GameSession.main_character)
	if GameSession.teammate != &"":
		ids.append(GameSession.teammate)
	if ids.is_empty():
		# Repli démo : un DUO, pour que l'allié apparaisse dans la file de rencontre tant
		# que la partie n'initialise pas main_character/teammate. draka = perso principal ;
		# kalilk n'est qu'un bouche-trou de coéquipier (il a un sprite, donc son portrait
		# de file est visible) — le vrai coéquipier est la 2e personnalité du duo, sans
		# espèce ni asset dédié pour l'instant.
		ids = [&"draka", &"kalilk"]
	return ids
