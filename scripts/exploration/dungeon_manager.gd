## Grille logique d'un donjon : cases praticables, occupation, tours, rivaux.
##
## Source de vérité de la navigation (et non des raycasts physiques dispersés comme
## dans le proto Unity). Le joueur et les rivaux INTERROGENT ce gestionnaire au lieu
## de sonder la scène. Une case = [Vector3i] (x, niveau y, z) ; le monde = case * CELL_SIZE.
##
## L'exploration est par tours : un pas du joueur appelle [method advance_turn], ce qui
## fait jouer les rivaux. (Règle « rotation = tour ? » : à brancher ici si besoin — la
## doc Notion ne tranche pas, le proto comptait la rotation comme un tour.)
##
## Découvert par le joueur / les rivaux via le groupe "dungeon".
##
## ÉCHELLE : 1 unité Godot = 1 mètre. Une case (et donc un bloc de mur) fait 1 m³ ; les
## personnages sont petits (yeux à [constant EYE_HEIGHT]), donc un mur d'une case cache
## complètement la vue. Une case (x, y, z) occupe le volume qui va de son SOL, à
## y * CELL_SIZE, jusqu'à un CELL_SIZE au-dessus. [method cell_to_world] retourne ce sol :
## c'est le point où un acteur se tient (pieds), et l'origine à laquelle les mécanismes
## posent leur visuel.
class_name DungeonManager
extends Node3D

## Taille d'une case en unités monde (mètres). Un bloc de mur = 1 m × 1 m × 1 m.
const CELL_SIZE := 1.0

## Hauteur des yeux d'un personnage, en mètres. Sous la hauteur d'un mur : on ne voit
## jamais par-dessus. Appliquée par le rig caméra du joueur (voir `player.tscn`).
const EYE_HEIGHT := 0.6

## Épaisseur d'une dalle de sol (= du plafond de la case du dessous). Non nulle mais fine :
## sous un étage supérieur il reste CELL_SIZE - FLOOR_THICKNESS de dégagement, largement de
## quoi passer pour un personnage haut de ~[constant EYE_HEIGHT]. Un sol d'étage n'est donc
## PAS un bloc plein : on peut marcher dessous s'il y a un sol à ce niveau-là.
##
## Une dalle n'est posée que là où le sol surplombe du VIDE ou un étage navigable : au-dessus
## d'un bloc de mur, c'est la face haute du mur qui sert de sol (doc « Walls + Decors » : « a
## wall can be stacked or serve as ground on the floor above it »), ce qui évite de doubler la
## géométrie et allège le level design.
const FLOOR_THICKNESS := 0.1

## Épaisseur d'un élément posé SUR l'arête entre deux cases plutôt que sur une case : porte
## ([Gateway]) ou rambarde. Il n'occupe donc aucune case, et reste assez fin pour qu'un acteur
## tienne de chaque côté.
const EDGE_THICKNESS := 0.1

## Dégâts d'une chute de `levels` unités de hauteur.
##
## Doc « Game Design / Gameplay Elements / Mechanisms + Heights » : « when jumping down 2+
## height units, both player characters get 10 damage, plus 5 damage per additional height
## unit ». Une chute d'UNE seule unité ne coûte donc rien. Règle de donjon partagée : elle vaut
## pour le joueur comme pour les rivaux (doc « Rivals »).
static func fall_damage(levels: int) -> int:
	if levels < 2:
		return 0
	return 10 + 5 * (levels - 2)

signal turn_advanced(turn: int)
## Émis quand un déplacement aboutit sur la case d'un individu adverse.
signal encounter_requested(rival: Node, initiated_by_rival: bool)

## Un rival arrive sur la case de pont étroit occupée par le joueur : les deux tombent.
signal bridge_collision(rival: Node, tile: Vector3i)

## Message ponctuel destiné au joueur (résultat d'un dieverting, plus tard piège déclenché,
## objet trouvé…). Les mécanismes le postent via [method post_message] et le HUD l'affiche :
## un mécanisme n'a pas à connaître l'UI.
signal message_posted(text: String)

## Démo (échafaudage) : construit une salle rectangulaire au boot pour pouvoir tester
## la boucle d'exploration sans donjon authoring. Mettre demo_build=false pour un vrai
## donjon (dont la grille sera fournie autrement).
@export var demo_build := false
@export var demo_width := 9
@export var demo_depth := 9
@export var demo_interior_walls: Array[Vector3i] = []

var turn_count := 0

# Cases praticables (sol). cell:Vector3i -> true.
var _floor: Dictionary = {}
# Occupation : cell:Vector3i -> Node (rival). Le joueur n'occupe PAS (il déclenche
# une rencontre s'il entre sur une case occupée).
var _occupants: Dictionary = {}

# Mécanismes par case : cell:Vector3i -> Array[mécanisme]. Plusieurs mécanismes peuvent
# cohabiter sur une même case. Enregistrés par les nœuds mécanisme au boot.
var _mechanisms: Dictionary = {}

# Cases rendues en blocs de mur, mémorisées par [method render_grid]. La mini-map les dessine :
# une salle se lit par son pourtour, pas seulement par l'absence de sol.
var _walls: Dictionary = {}

# Mécanismes d'ARÊTE (portes) : ils ne sont sur aucune case mais sur la frontière entre deux
# cases voisines. Clé canonique [method edge_key] -> Array[mécanisme].
var _edge_mechanisms: Dictionary = {}

# Cases explicitement VIDES (trou franc voulu par le level design) : jamais rendues en mur,
# même si rien ne les soutient. Y entrer, c'est une chute SANS FOND — mortelle (voir
# [method is_bottomless]). Une case simplement « absente » reste, elle, un mur : c'est le cas
# normal du pourtour d'une salle.
var _hole: Dictionary = {}

# Cases « fosse » (sol plus BAS, ravin) : rendues comme une dalle sombre abaissée, jamais
# comme un mur, et sans dalle normale si la case est aussi praticable (planche du pont posée
# par-dessus). Sert au visuel « tronc au-dessus d'un sol en contrebas ».
var _pit: Dictionary = {}
## Profondeur (mètres) de la dalle de fosse sous le niveau de sol normal.
const PIT_DEPTH := 1.2

var _player: Node3D
var _rivals: Array[Node] = []


func _ready() -> void:
	add_to_group("dungeon")
	if demo_build:
		build_demo_room(demo_width, demo_depth, demo_interior_walls)


# --------------------------------------------------------------------------
# Conversions monde <-> grille
# --------------------------------------------------------------------------

func world_to_cell(pos: Vector3) -> Vector3i:
	return Vector3i(roundi(pos.x / CELL_SIZE), roundi(pos.y / CELL_SIZE), roundi(pos.z / CELL_SIZE))

## Point monde au SOL de la case, en son centre : là où un acteur pose les pieds. Le volume
## de la case va de là jusqu'à [constant CELL_SIZE] au-dessus.
func cell_to_world(cell: Vector3i) -> Vector3:
	return Vector3(cell.x, cell.y, cell.z) * CELL_SIZE


# --------------------------------------------------------------------------
# Praticabilité & occupation
# --------------------------------------------------------------------------

func is_floor(cell: Vector3i) -> bool:
	return _floor.has(cell)

## Une case est franchissable si c'est du sol, non occupée, et non bloquée par un mécanisme
## (obstacle indestructible…). Ne dit RIEN des portes, qui barrent une arête et non une case :
## pour un pas, passer par [method can_step].
func is_walkable(cell: Vector3i) -> bool:
	return _floor.has(cell) and not _occupants.has(cell) and not is_blocked_by_mechanism(cell)

## Un pas de `from_cell` vers `to_cell` (cases voisines) est-il possible ? = case d'arrivée
## franchissable ET arête non barrée (porte fermée entre les deux).
func can_step(from_cell: Vector3i, to_cell: Vector3i) -> bool:
	return is_walkable(to_cell) and not is_edge_blocked(from_cell, to_cell)

## Un mécanisme de la case interdit-il le passage ? (indépendant de l'occupation.)
func is_blocked_by_mechanism(cell: Vector3i) -> bool:
	for m in mechanisms_at(cell):
		if m.blocks_walk():
			return true
	return false

func occupant_at(cell: Vector3i) -> Node:
	return _occupants.get(cell)

## Réserve une case pour un occupant. Échoue si déjà occupée ou hors sol.
func reserve(cell: Vector3i, who: Node) -> bool:
	if not _floor.has(cell) or _occupants.has(cell):
		return false
	_occupants[cell] = who
	return true

func release(cell: Vector3i) -> void:
	_occupants.erase(cell)

func move_occupant(from_cell: Vector3i, to_cell: Vector3i, who: Node) -> bool:
	if not can_step(from_cell, to_cell):
		return false
	_occupants.erase(from_cell)
	_occupants[to_cell] = who
	return true


# --------------------------------------------------------------------------
# Acteurs & tours
# --------------------------------------------------------------------------

func register_player(player: Node3D) -> void:
	_player = player

func player_cell() -> Vector3i:
	return world_to_cell(_player.global_position) if _player else Vector3i.ZERO

## Vrai si `who` est le personnage joueur (et non un rival). Sert aux mécanismes qui ne
## profitent qu'au joueur (loot de coffre, dieverting…).
func is_player(who: Node) -> bool:
	return who != null and who == _player

## Vrai si les rivaux doivent ignorer le joueur (invisible / non-poursuivi via fog mantel,
## torment veil, costume…). Consulté par la détection des rivaux.
func rivals_ignore_player() -> bool:
	return is_instance_valid(_player) and _player.has_method("is_hidden_from_rivals") \
		and _player.is_hidden_from_rivals()

func register_rival(rival: Node) -> void:
	if rival in _rivals:
		return
	_rivals.append(rival)
	reserve(world_to_cell(rival.global_position), rival)

func unregister_rival(rival: Node) -> void:
	_rivals.erase(rival)

## Avance d'un tour : notifie, fait jouer chaque rival, puis cadence les mécanismes et fait
## s'écouler les afflictions (poison…). Point d'intégration unique du modèle de tour.
## Appelé par le joueur après un pas réussi.
##
## ## TODO(doc « Game Design / Dungeon Exploration ») : l'ordre du tour de la doc compte QUATRE
## phases — « player, then reveal of dungeon mechanisms (traps), then other spirimonsters, then
## dungeon mechanisms activation ». Il manque ici la phase de RÉVÉLATION, qui doit s'intercaler
## AVANT le jeu des rivaux : aujourd'hui un piège ne se dévoile qu'en se déclenchant
## ([code]trap.on_enter[/code] pose `revealed`), et [code]trap.reveal()[/code] n'a aucun site
## d'appel. Cette phase est le point d'accrochage attendu du talent `reveal_traps` (razél) et de
## `trick_to_reveal` (érzélak).
func advance_turn() -> void:
	turn_count += 1
	turn_advanced.emit(turn_count)
	var pcell := player_cell()
	for rival in _rivals.duplicate():
		if is_instance_valid(rival) and rival.has_method("take_turn"):
			rival.take_turn(pcell)
	# Mécanismes cadencés (gates automatisées, etc.), sur case comme sur arête.
	for dict in [_mechanisms, _edge_mechanisms]:
		for arr in dict.values():
			for m in arr:
				if is_instance_valid(m):
					m.on_turn(turn_count)
	# Effets persistants par acteur (poison), après le jeu des rivaux.
	_tick_actor_afflictions()

## Fait s'écouler les afflictions du joueur et des rivaux. Chaque acteur applique lui-même
## son effet (poison → DEN), le manager reste découplé.
func _tick_actor_afflictions() -> void:
	if is_instance_valid(_player) and _player.has_method("on_turn_elapsed"):
		_player.on_turn_elapsed()
	for rival in _rivals.duplicate():
		if is_instance_valid(rival) and rival.has_method("on_turn_elapsed"):
			rival.on_turn_elapsed()

## Poste un message de feedback à destination du joueur (texte DÉJÀ traduit).
func post_message(text: String) -> void:
	message_posted.emit(text)

## Demande de rencontre (relayée par le joueur ou un rival).
func request_encounter(rival: Node, initiated_by_rival: bool) -> void:
	encounter_requested.emit(rival, initiated_by_rival)

## Deux personnages se croisent sur la MÊME case de pont étroit : les deux tombent (doc).
## Le cas joueur+rival est arbitré par `exploration.gd`, qui pilote la traversée du joueur.
func request_bridge_collision(rival: Node, tile: Vector3i) -> void:
	bridge_collision.emit(rival, tile)

## Rivaux enregistrés (copie : l'appelant peut en dissoudre pendant l'itération).
func rivals() -> Array[Node]:
	return _rivals.duplicate()

## Un acteur vient de CHANGER D'ÉTAGE — chute, escalier, et demain ascenseur ou autre. Les
## rivaux qui l'ont vu partir peuvent le poursuivre par leurs propres moyens.
##
## Point de diffusion unique : tout mécanisme qui déplace le joueur d'un étage à l'autre doit
## passer par ici, plutôt que de prévenir les rivaux lui-même.
func notify_level_change(who: Node, from_cell: Vector3i, to_cell: Vector3i) -> void:
	if not is_player(who):
		return
	for rival in _rivals.duplicate():
		if is_instance_valid(rival) and rival.has_method("witness_player_level_change"):
			rival.witness_player_level_change(from_cell, to_cell)

## Une case de pont étroit ? (mécanisme exposant le test d'équilibre.)
func is_narrow_bridge(cell: Vector3i) -> bool:
	for m in mechanisms_at(cell):
		if m.has_method("engage") and m.has_method("direction"):
			return true
	return false

## Case de sol libre la plus proche de `cell` (`cell` elle-même si elle est libre), pour
## poser un acteur sans casser l'invariant « un occupant par case ». Retourne `cell` si
## rien n'est libre alentour (à l'appelant de décider quoi en faire).
func free_cell_near(cell: Vector3i) -> Vector3i:
	if is_floor(cell) and occupant_at(cell) == null:
		return cell
	for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		var n: Vector3i = cell + d
		if is_walkable(n) and occupant_at(n) == null:
			return n
	return cell

## Cases de sol libres AUTOUR de `cell`, au même étage, dans un rayon de `radius` cases
## (distance de Manhattan), mélangées. `cell` elle-même est exclue. Sert à faire apparaître
## des acteurs « à proximité » sans se soucier de la forme de la salle.
func free_cells_near(cell: Vector3i, radius: int) -> Array[Vector3i]:
	var found: Array[Vector3i] = []
	for dx in range(-radius, radius + 1):
		for dz in range(-radius, radius + 1):
			if absi(dx) + absi(dz) > radius or (dx == 0 and dz == 0):
				continue
			var c := cell + Vector3i(dx, 0, dz)
			if is_walkable(c) and occupant_at(c) == null:
				found.append(c)
	found.shuffle()
	return found


# --------------------------------------------------------------------------
# Mécanismes de donjon (pièges, gates, sols spéciaux…)
# --------------------------------------------------------------------------

## Enregistre un mécanisme sur une case (appelé par le nœud mécanisme au boot).
func register_mechanism(cell: Vector3i, mechanism: Node) -> void:
	var arr: Array = _mechanisms.get(cell, [])
	if mechanism not in arr:
		arr.append(mechanism)
	_mechanisms[cell] = arr

func unregister_mechanism(cell: Vector3i, mechanism: Node) -> void:
	var arr: Array = _mechanisms.get(cell, [])
	arr.erase(mechanism)
	if arr.is_empty():
		_mechanisms.erase(cell)
	else:
		_mechanisms[cell] = arr

## Mécanismes présents sur une case (vide si aucun).
func mechanisms_at(cell: Vector3i) -> Array:
	return _mechanisms.get(cell, [])


# --------------------------------------------------------------------------
# Mécanismes d'arête (portes) — entre les cases, pas sur une case
# --------------------------------------------------------------------------

## Clé canonique de l'arête entre deux cases voisines : indépendante de l'ordre, donc la même
## depuis les deux côtés. Vector4i(x, y, z, axe) où (x,y,z) est la case la plus « basse » des
## deux dans l'axe considéré et axe = 0 (frontière selon X) ou 1 (selon Z).
static func edge_key(from_cell: Vector3i, to_cell: Vector3i) -> Vector4i:
	var lo := from_cell
	var d := to_cell - from_cell
	if d.x + d.z < 0:
		lo = to_cell
		d = -d
	var axis := 0 if d.x != 0 else 1
	return Vector4i(lo.x, lo.y, lo.z, axis)

## Enregistre un mécanisme sur l'arête entre deux cases voisines (appelé par le nœud au boot).
func register_edge_mechanism(from_cell: Vector3i, to_cell: Vector3i, mechanism: Node) -> void:
	var key := edge_key(from_cell, to_cell)
	var arr: Array = _edge_mechanisms.get(key, [])
	if mechanism not in arr:
		arr.append(mechanism)
	_edge_mechanisms[key] = arr

func unregister_edge_mechanism(from_cell: Vector3i, to_cell: Vector3i, mechanism: Node) -> void:
	var key := edge_key(from_cell, to_cell)
	var arr: Array = _edge_mechanisms.get(key, [])
	arr.erase(mechanism)
	if arr.is_empty():
		_edge_mechanisms.erase(key)
	else:
		_edge_mechanisms[key] = arr

## Mécanismes posés sur l'arête entre deux cases voisines (vide si aucun).
func edge_mechanisms_between(from_cell: Vector3i, to_cell: Vector3i) -> Array:
	return _edge_mechanisms.get(edge_key(from_cell, to_cell), [])

## Le passage d'une case à sa voisine est-il barré (porte fermée, rambarde) ? Symétrique.
func is_edge_blocked(from_cell: Vector3i, to_cell: Vector3i) -> bool:
	for m in edge_mechanisms_between(from_cell, to_cell):
		if m.blocks_walk():
			return true
	return false

## L'arête est-elle OPAQUE (porte fermée) ? Une rambarde barre le pas mais pas la vue.
func is_edge_opaque(from_cell: Vector3i, to_cell: Vector3i) -> bool:
	for m in edge_mechanisms_between(from_cell, to_cell):
		if m.blocks_sight():
			return true
	return false

## Diffuse l'entrée d'un acteur sur une case à ses mécanismes (activation des pièges…).
## Appelé par le joueur / les rivaux après un pas logiquement abouti.
func notify_entered(cell: Vector3i, who: Node) -> void:
	for m in mechanisms_at(cell).duplicate():
		if is_instance_valid(m):
			m.on_enter(who)

## Actions contextuelles disponibles pour un acteur sur `from_cell` regardant `facing` :
## agrège les actions « sur la case » des mécanismes de `from_cell` (ex. Dig), les actions
## « adjacentes » des mécanismes de la case regardée `from_cell + facing` (ex. Recycle,
## Examine) et celles des mécanismes posés sur l'arête regardée (portes : ouvrir, méditer —
## accessibles des deux côtés). Consommé par la surface d'actions d'exploration (HUD).
func actions_for(from_cell: Vector3i, facing: Vector3i, who: Node) -> Array:
	var actions: Array = []
	for m in mechanisms_at(from_cell):
		actions.append_array(m.on_tile_actions(who))
	for m in edge_mechanisms_between(from_cell, from_cell + facing):
		actions.append_array(m.on_adjacent_actions(who, facing))
	# Ce qui coupe la vue coupe l'interaction : rien de ce qui est DERRIÈRE une porte fermée
	# n'est actionnable (ses propres actions, elles, restent offertes — c'est sur elle qu'on
	# agit). Par-dessus une rambarde, en revanche, on voit et on agit.
	if is_edge_opaque(from_cell, from_cell + facing):
		return actions
	for m in mechanisms_at(from_cell + facing):
		actions.append_array(m.on_adjacent_actions(who, facing))
	return actions

## Une case de sol franchissable choisie au hasard, différente de `exclude`. Retourne
## `exclude` si aucune n'est disponible.
func random_floor_cell(exclude: Vector3i) -> Vector3i:
	var candidates: Array = []
	for c in _floor:
		if c != exclude and is_walkable(c):
			candidates.append(c)
	if candidates.is_empty():
		return exclude
	return candidates[randi() % candidates.size()]

## Téléporte un acteur vers une case de sol libre au hasard (piège de téléportation).
## Retourne la case d'arrivée (inchangée si aucune destination libre).
func teleport_actor(who: Node) -> Vector3i:
	var from: Vector3i = who.cell
	return teleport_actor_to(who, random_floor_cell(from))

## Téléporte un acteur vers une case PRÉCISE (entrée / sortie de donjon, dieverting…). Se
## rabat sur une case libre voisine si la destination est occupée. Gère l'occupation (les
## rivaux occupent leur case, pas le joueur). Retourne la case d'arrivée (inchangée si la
## destination n'est pas praticable). Ne redéclenche PAS les mécanismes de la case d'arrivée
## (relocalisation instantanée).
func teleport_actor_to(who: Node, dest: Vector3i) -> Vector3i:
	var from: Vector3i = who.cell
	if not is_floor(dest):
		return from
	dest = free_cell_near(dest)
	if dest == from:
		return from
	var occ := occupant_at(dest)
	if occ != null and occ != who:
		return from  # rien de libre à l'arrivée : on ne délogera personne
	if _occupants.get(from) == who:
		_occupants.erase(from)
		_occupants[dest] = who
	if who.has_method("teleport_to"):
		who.teleport_to(dest)
	return dest


# --------------------------------------------------------------------------
# Entrée & sorties du donjon
# --------------------------------------------------------------------------
#
# Doc « Level Design / Dungeons » : on quitte un donjon en atteignant une SORTIE et en
# interagissant avec elle, et « the dungeon entry counts as an exit point ». Ces cases sont
# déclarées par le level design (en dev, par le scénario de test) ; elles servent aujourd'hui
# aux mécanismes qui y renvoient le joueur (dieverting).
# ## TODO: la sortie de donjon proprement dite (interaction, retour carte du monde, sortie
# après dévitalisation du duo) reste à brancher — cf. `exploration.gd`.

var _entrance: Vector3i
var _has_entrance := false
var _exits: Array[Vector3i] = []

## Déclare la case d'entrée. Elle compte AUSSI comme sortie (règle doc), inutile de
## l'ajouter deux fois.
func set_entrance(cell: Vector3i) -> void:
	_entrance = cell
	_has_entrance = true
	add_exit(cell)

func has_entrance() -> bool:
	return _has_entrance

## Case d'entrée du donjon (Vector3i.ZERO tant qu'aucune n'est déclarée : tester
## [method has_entrance] avant de s'en servir).
func entrance_cell() -> Vector3i:
	return _entrance

## Déclare une case de sortie (secondaire ou principale).
func add_exit(cell: Vector3i) -> void:
	if cell not in _exits:
		_exits.append(cell)

func exit_cells() -> Array[Vector3i]:
	return _exits.duplicate()

func has_exit() -> bool:
	return not _exits.is_empty()

## Une sortie au hasard (doc : « at random if more than one »). Retourne Vector3i.ZERO si
## aucune n'est déclarée : tester [method has_exit] avant.
func random_exit() -> Vector3i:
	if _exits.is_empty():
		return Vector3i.ZERO
	return _exits[randi() % _exits.size()]


# --------------------------------------------------------------------------
# Construction de la grille
# --------------------------------------------------------------------------

func set_floor_cells(cells: Array) -> void:
	_floor.clear()
	for c in cells:
		_floor[c] = true

func add_floor(cell: Vector3i) -> void:
	_floor[cell] = true

## Marque une case comme « fosse » : praticable, mais [method render_grid] n'y pose NI dalle
## normale NI mur — la case n'est tenue que par ce que le level design y met (planche de pont).
## Si aucun sol réel n'existe en dessous, une dalle sombre de fond est posée en contrebas pour
## que le vide ne soit pas béant ; sinon c'est le sol du dessous qui fait office de fond.
func mark_pit(cell: Vector3i) -> void:
	_pit[cell] = true

## Marque une case comme trou franc : pas de mur pour la boucher, et pas de fond non plus.
func mark_hole(cell: Vector3i) -> void:
	_hole[cell] = true

func is_hole(cell: Vector3i) -> bool:
	return _hole.has(cell)

## Entrer sur cette case déclenche-t-il une chute SANS FOND ? Une telle chute ne devrait pas
## exister (erreur de level design) : le pourtour d'une salle est rendu en mur justement parce
## que rien ne le soutient. Si le level design en laisse une malgré tout, elle est traitée comme
## ce qu'elle est — un sol trop bas pour qu'on y survive : chute fatale, et non blocage muet.
func is_bottomless(cell: Vector3i) -> bool:
	return _hole.has(cell) and not _floor.has(cell) and fall_landing(cell) == cell

## Case d'atterrissage d'une chute depuis `cell` : première case de SOL sous `cell` (niveau
## inférieur). Retourne `cell` inchangée si aucune (donc pas de chute : mur).
func fall_landing(cell: Vector3i) -> Vector3i:
	for level in range(cell.y - 1, cell.y - 12, -1):
		var below := Vector3i(cell.x, level, cell.z)
		if _floor.has(below):
			return below
	return cell

## Génère la géométrie visible depuis la grille LOGIQUE : un bloc de mur d'une case sur chaque
## case non-sol adjacente à du sol (pourtour), et une DALLE MINCE (épaisseur
## [constant FLOOR_THICKNESS], qui fait aussi office de plafond pour la case du dessous) sur
## chaque case de sol qui n'a PAS de mur en dessous — là où il y a un mur, c'est sa face haute
## qui sert de sol (doc « Walls + Decors »). Les cases portant un mécanisme ne reçoivent pas de
## mur (le mécanisme pose son propre marqueur). À appeler après avoir peuplé le sol et les
## mécanismes (ex. par un scénario de test).
func render_grid() -> void:
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.24, 0.24, 0.30)
	# Les murs sont dérivés d'abord : une case de sol posée SUR un mur n'a pas besoin de dalle.
	var wall_cells := _derive_wall_cells()
	_walls = wall_cells  # mémorisés pour la mini-map, qui les redessine à chaque frame
	for c in _floor:
		if _pit.has(c):
			continue  # dalle abaissée rendue plus bas (planche du pont posée par-dessus)
		if wall_cells.has(c + Vector3i.DOWN):
			continue  # un bloc de mur tient lieu de sol : pas de dalle par-dessus
		add_child(_make_slab(cell_to_world(c), floor_mat))
	# Fosses : dalle de fond sombre en contrebas UNIQUEMENT s'il n'y a pas déjà un vrai sol
	# plus bas (sinon on masquerait le ravin dans lequel on est censé pouvoir tomber).
	var pit_mat := StandardMaterial3D.new()
	pit_mat.albedo_color = Color(0.12, 0.12, 0.16)
	for c in _pit:
		if fall_landing(c) != c:
			continue  # un étage inférieur sert déjà de fond
		add_child(_make_slab(cell_to_world(c) + Vector3(0.0, -PIT_DEPTH, 0.0), pit_mat))
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.14, 0.14, 0.17)
	for w in wall_cells:
		# Un mur surmonté d'une case de sol porte le revêtement de sol sur sa face haute :
		# c'est LUI le sol de l'étage au-dessus.
		var top_mat: StandardMaterial3D = floor_mat if _floor.has(w + Vector3i.UP) else null
		add_child(_make_wall_block(cell_to_world(w), wall_mat, top_mat))

## Cases rendues en blocs de mur (vide tant que [method render_grid] n'a pas tourné).
func wall_cells() -> Dictionary:
	return _walls

func is_wall(cell: Vector3i) -> bool:
	return _walls.has(cell)

## TODO (2026-09-02) — DETTE D'AUTHORING. Murs et trous sont aujourd'hui DÉDUITS de la seule
## grille de sols : un mur, c'est « rien ici, et rien en dessous », et un trou franc n'existe que
## si quelqu'un appelle [method mark_hole] (personne ne le fait, hors contrôle headless). Deux
## règles de la doc reposent donc sur une déduction plutôt que sur une déclaration :
##  - « a wall can serve as ground on the floor above it » (pas de dalle au-dessus d'un mur) ;
##  - « if an endless fall happens anyway, it devitalises » (le trou franc).
## Quand le format d'authoring de donjon existera, les murs et les trous devront être DÉCLARÉS
## (comme les sols le sont), et [method _derive_wall_cells] ne servira plus que d'échafaudage
## pour les scénarios de test bâtis par code.
##
## Cases rendues comme blocs de mur : cases non-sol adjacentes à du sol, sans mécanisme ni
## fosse, et sans sol en contrebas (un bord de chute reste ouvert, pas muré).
func _derive_wall_cells() -> Dictionary:
	var wall_cells := {}
	for c in _floor:
		for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			var n: Vector3i = c + d
			if _hole.has(n):
				continue  # trou voulu : surtout pas de mur pour le boucher
			if not _floor.has(n) and not _mechanisms.has(n) and not _pit.has(n) and fall_landing(n) == n:
				wall_cells[n] = true
	return wall_cells

## Dalle mince (sol/plafond) posée sur une case : sa face HAUTE est au niveau `floor_pos`,
## son épaisseur descend en dessous.
func _make_slab(floor_pos: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(CELL_SIZE, FLOOR_THICKNESS, CELL_SIZE)
	mi.mesh = box
	mi.material_override = mat
	mi.position = floor_pos + Vector3(0.0, -FLOOR_THICKNESS * 0.5, 0.0)
	return mi

## Bloc de mur plein : un cube d'une case, qui remplit le volume de la case au-dessus de son
## sol (donc jamais plus haut qu'un étage — l'étage du dessus reste libre).
##
## `top_mat` non nul = une case de sol repose sur ce mur : on plaque le revêtement de sol sur
## sa face haute (aucune dalle n'est posée par-dessus, c'est le mur qui EST le sol).
func _make_wall_block(floor_pos: Vector3, mat: StandardMaterial3D,
		top_mat: StandardMaterial3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(CELL_SIZE, CELL_SIZE, CELL_SIZE)
	mi.mesh = box
	mi.material_override = mat
	if top_mat != null:
		var skin := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(CELL_SIZE, CELL_SIZE)
		skin.mesh = plane
		skin.material_override = top_mat
		skin.position = Vector3(0.0, CELL_SIZE * 0.5 + 0.002, 0.0)  # juste au-dessus de la face
		mi.add_child(skin)
	mi.position = floor_pos + Vector3(0.0, CELL_SIZE * 0.5, 0.0)
	return mi

## Construit une salle de démonstration : sol rectangulaire (niveau 0) avec quelques
## murs intérieurs, + un rendu minimal (sol plat + boîtes de murs). Échafaudage : les
## vrais donjons seront des scènes 3D authoring, dont la grille sera dérivée autrement.
func build_demo_room(width: int, depth: int, interior_walls: Array = []) -> void:
	var blocked := {}
	for w in interior_walls:
		blocked[w] = true
	var cells: Array = []
	for x in range(width):
		for z in range(depth):
			var c := Vector3i(x, 0, z)
			if not blocked.has(c):
				cells.append(c)
	set_floor_cells(cells)
	_spawn_demo_visuals(width, depth, blocked)

func _spawn_demo_visuals(width: int, depth: int, blocked: Dictionary) -> void:
	# Sol unique (au niveau du sol des cases, y = 0).
	var floor_mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(width * CELL_SIZE, depth * CELL_SIZE)
	floor_mi.mesh = plane
	floor_mi.position = Vector3((width - 1) * CELL_SIZE * 0.5, 0.0, (depth - 1) * CELL_SIZE * 0.5)
	add_child(floor_mi)
	# Murs : pourtour + murs intérieurs.
	var wall_cells := {}
	for x in range(-1, width + 1):
		wall_cells[Vector3i(x, 0, -1)] = true
		wall_cells[Vector3i(x, 0, depth)] = true
	for z in range(-1, depth + 1):
		wall_cells[Vector3i(-1, 0, z)] = true
		wall_cells[Vector3i(width, 0, z)] = true
	for w in blocked:
		wall_cells[w] = true
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.14, 0.14, 0.17)
	for cell in wall_cells:
		add_child(_make_wall_block(cell_to_world(cell), wall_mat))
