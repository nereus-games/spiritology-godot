## Catalogue de scénarios de TEST (dev) : chaque scénario peuple un [DungeonManager] avec un
## sous-ensemble de mécanismes pour tester un élément à la fois, sans tout monter d'un coup.
##
## Deux moitiés, séparées à dessein : les TEXTES (titre, mode d'emploi) sont des [ScenarioData]
## dans `data/scenarios/`, éditables sans toucher au code ; la CONSTRUCTION du donjon est le
## code ci-dessous, un constructeur par scénario. L'`id` relie les deux, et
## `data_integrity_check` vérifie qu'aucun des deux côtés ne pointe dans le vide.
##
## `selected_id` est posé par l'écran de sélection puis lu par `exploration.gd`, qui appelle
## [method build] et place le joueur à la case retournée. Le bouton MENU du HUD renvoie à
## l'écran de sélection (temporaire).
##
## Pas de `class_name` (piège du cache CLI) : référencé par `preload`. Réf. autoloads + scripts
## de mécanismes (OK en jeu, chargé après le boot).
extends RefCounted

const Trap := preload("res://scripts/exploration/mechanisms/trap.gd")
const Gateway := preload("res://scripts/exploration/mechanisms/gateway.gd")
const CrumblyGround := preload("res://scripts/exploration/mechanisms/crumbly_ground.gd")
const Litter := preload("res://scripts/exploration/mechanisms/litter.gd")
const Chest := preload("res://scripts/exploration/mechanisms/chest.gd")
const RefreshCrystal := preload("res://scripts/exploration/mechanisms/refresh_crystal.gd")
const Dieverting := preload("res://scripts/exploration/mechanisms/dieverting.gd")
const CrackedWall := preload("res://scripts/exploration/mechanisms/cracked_wall.gd")
const ExaminableDecor := preload("res://scripts/exploration/mechanisms/examinable_decor.gd")
const NarrowBridge := preload("res://scripts/exploration/mechanisms/narrow_bridge.gd")
const Stairs := preload("res://scripts/exploration/mechanisms/stairs.gd")
const Elevator := preload("res://scripts/exploration/mechanisms/elevator.gd")
const Guardrail := preload("res://scripts/exploration/mechanisms/guardrail.gd")
const AbilityCatalog := preload(
	"res://scripts/exploration/abilities/exploration_ability_catalog.gd"
)
const RIVAL_SCENE := preload("res://scenes/exploration/rival/rival.tscn")

## Scénario choisi dans l'écran de sélection (défaut : premier).
static var selected_id: StringName = &"movement"

## Espèces que le mini-quiz peut donner au PERSONNAGE PRINCIPAL (doc Notion « Story +
## Characters / Introduction / Mini Personality Quiz », section Available Results).
const MAIN_SPECIES: Array[StringName] = [&"ravbak", &"akturlin", &"erzelak", &"zuk"]

## Espèces que le mini-quiz peut donner au COÉQUIPIER : les mêmes que pour le principal,
## plus six autres (doc, même section). Le duo peut porter deux fois la même espèce.
const TEAMMATE_SPECIES: Array[StringName] = [
	&"ravbak",
	&"akturlin",
	&"erzelak",
	&"zuk",
	&"razel",
	&"jezal",
	&"gelmi",
	&"granop",
	&"fopin",
	&"spodra",
]

## DEV : duo imposé aux scénarios, choisi dans l'écran de sélection. En vrai c'est le
## mini-quiz de personnalité qui l'attribue ; ici on le choisit à la main, en restant dans
## les résultats que le quiz peut donner à chacun des deux rôles.
static var main_species: StringName = &"ravbak"
static var teammate_species: StringName = &"razel"

## DEV : DEN maximal imposé aux rivaux des scénarios, réglé au curseur dans l'écran de
## sélection. Le DEN d'un rival est normalement un réglage de LEVEL DESIGN (donjon par donjon) ;
## ce curseur est là pour l'éprouver à la main. 0 = valeur par défaut du rival.
static var rival_den_override := 0

const SCENARIO_DIR := "res://data/scenarios/"

## Fiches des scénarios, dans l'ordre de l'écran de sélection. Le dossier se lit par ordre
## alphabétique : c'est [member ScenarioData.order] qui fixe la progression voulue.
static var _list: Array = []


static func list() -> Array:
	if not _list.is_empty():
		return _list
	var dir := DirAccess.open(SCENARIO_DIR)
	if dir == null:
		push_error("[ScenarioCatalog] dossier introuvable : %s" % SCENARIO_DIR)
		return _list
	for f in dir.get_files():
		if f.ends_with(".tres"):
			var res := load(SCENARIO_DIR + f) as ScenarioData
			if res != null:
				_list.append(res)
	_list.sort_custom(func(a, b): return a.order < b.order)
	return _list


static func title_for(id: StringName) -> String:
	for s in list():
		if s.id == id:
			return s.title
	return String(id)


## Construit le scénario dans `dm` et retourne la case de départ du joueur.
static func build(id: StringName, dm) -> Vector3i:
	_reset_session()
	match id:
		&"movement":
			return _movement(dm)
		&"traps":
			return _traps(dm)
		&"gates":
			return _gates(dm)
		&"grounds":
			return _grounds(dm)
		&"chests":
			return _chests(dm)
		&"walls":
			return _walls(dm)
		&"bridge":
			return _bridge(dm)
		&"bridge_rival":
			return _bridge_rival(dm)
		&"stairs":
			return _stairs(dm)
		&"abilities":
			return _abilities(dm)
	# Retomber en silence sur un autre scénario a fait croire pendant un moment qu'un id
	# inconnu « marchait ». On construit toujours quelque chose pour ne pas planter le jeu,
	# mais on le dit — et les checks échouent sur une erreur signalée.
	push_error("[ScenarioCatalog] scénario sans constructeur : %s" % id)
	return _traps(dm)


# --------------------------------------------------------------------------
# Outils de construction
# --------------------------------------------------------------------------


static func _reset_session() -> void:
	GameSession.inventory.clear()
	GameSession.used_exploration_abilities.clear()
	AbilityCatalog.dev_granted = []
	GameSession.set_den(GameSession.PartySlot.MAIN, GameSession.MAX_DEN)
	GameSession.set_den(GameSession.PartySlot.TEAMMATE, GameSession.MAX_DEN)
	GameSession.restore_party_eth()
	GameSession.main_character = main_species
	GameSession.teammate = teammate_species


static func _floor_rect(dm, x0: int, z0: int, w: int, d: int) -> void:
	for x in range(x0, x0 + w):
		for z in range(z0, z0 + d):
			dm.add_floor(Vector3i(x, 0, z))


static func _floor_line(dm, x: int, z0: int, length: int) -> void:
	for z in range(z0, z0 + length):
		dm.add_floor(Vector3i(x, 0, z))


## Sol rectangulaire à un ÉTAGE donné (y).
static func _floor_rect_y(dm, x0: int, z0: int, w: int, d: int, y: int) -> void:
	for x in range(x0, x0 + w):
		for z in range(z0, z0 + d):
			dm.add_floor(Vector3i(x, y, z))


## Instancie un mécanisme, applique `props`, le pose sur `cell` et l'ajoute au donjon.
static func _place(dm, script, cell: Vector3i, props: Dictionary = {}) -> Node:
	var m = script.new()
	for k in props:
		m.set(k, props[k])
	m.position = dm.cell_to_world(cell)
	dm.add_child(m)
	return m


static func _spawn_rival(dm, species: StringName, cell: Vector3i) -> Node:
	var r = RIVAL_SCENE.instantiate()
	r.species_id = species
	if rival_den_override > 0:
		r.max_den = rival_den_override  # posé AVANT l'entrée dans l'arbre (lu par _ready)
	r.position = dm.cell_to_world(cell)
	dm.add_child(r)
	return r


# --------------------------------------------------------------------------
# Scénarios
# --------------------------------------------------------------------------


static func _movement(dm) -> Vector3i:
	# Salle vide avec quelques piliers (cases retirées → rendues en murs) pour naviguer.
	_floor_rect(dm, 0, 0, 7, 9)
	for pillar in [
		Vector3i(2, 0, 3),
		Vector3i(4, 0, 3),
		Vector3i(3, 0, 6),
		Vector3i(1, 0, 6),
		Vector3i(5, 0, 6)
	]:
		dm._floor.erase(pillar)
	return Vector3i(3, 0, 0)


static func _traps(dm) -> Vector3i:
	_floor_rect(dm, 0, 0, 3, 9)
	_place(dm, Trap, Vector3i(1, 0, 2), {"kind": Trap.Kind.POISON, "revealed": true})
	_place(dm, Trap, Vector3i(1, 0, 4), {"kind": Trap.Kind.TELEPORT, "revealed": true})
	_place(dm, Trap, Vector3i(1, 0, 6), {"kind": Trap.Kind.DISARRAY, "revealed": true})
	return Vector3i(1, 0, 0)


static func _gates(dm) -> Vector3i:
	_floor_line(dm, 1, 0, 11)  # couloir 1 case de large : les portes bloquent vraiment
	# Les portes sont posées sur l'ARÊTE entre la case d'ancrage et la suivante (+z) : les deux
	# cases restent praticables, on peut donc attendre juste devant.
	var gate_edge := Vector3i(0, 0, 1)
	_place(dm, Gateway, Vector3i(1, 0, 3), {"kind": Gateway.Kind.AUTOMATED, "edge_dir": gate_edge})
	# Monnaie de CETTE porte : un choix de level design (la doc pose « pelles OU pierres
	# runiques » comme le choix de l'auteur, pas comme une alternative offerte au joueur).
	_place(
		dm,
		Gateway,
		Vector3i(1, 0, 6),
		{
			"kind": Gateway.Kind.LOCKED,
			"cost_tier": Gateway.CostTier.EARLY,
			"cost_currency": &"spade",
			"edge_dir": gate_edge
		}
	)
	_place(dm, Gateway, Vector3i(1, 0, 9), {"kind": Gateway.Kind.MEDITATION, "edge_dir": gate_edge})
	# Un tas DERRIÈRE la porte de méditation : tant qu'elle est fermée, elle cache ce tas, donc
	# ses actions (examine / recycle) ne sont pas proposées. Elles apparaissent une fois ouverte.
	_place(dm, Litter, Vector3i(1, 0, 10))
	GameSession.add_object(&"spade", 2)  # de quoi ouvrir la porte verrouillée
	return Vector3i(1, 0, 0)


static func _grounds(dm) -> Vector3i:
	_floor_rect(dm, 0, 0, 3, 5)
	_place(dm, CrumblyGround, Vector3i(1, 0, 1))
	_place(dm, Litter, Vector3i(1, 0, 3))
	GameSession.add_object(&"spade", 1)  # pour Dig
	AbilityCatalog.dev_granted = [&"fog_mantel"]  # une capacité à rafraîchir via Recycle
	GameSession.mark_exploration_ability_used(&"fog_mantel")
	return Vector3i(1, 0, 0)


static func _chests(dm) -> Vector3i:
	_floor_rect(dm, 0, 0, 3, 9)
	_place(dm, Chest, Vector3i(1, 0, 1))  # butin
	# Piège de téléportation déguisé. Avec razél dans le duo (talent Reveal Traps), il propose
	# le choix « se laisser téléporter / rester » au lieu de téléporter sec.
	_place(dm, Chest, Vector3i(1, 0, 3), {"is_trap": true})
	_place(dm, RefreshCrystal, Vector3i(0, 0, 2))  # obstacle, action refresh en adjacent
	# Deux dés : sur le premier le joueur a de quoi trancher (pelle), le second se déclenche
	# tout seul (la pelle a été dépensée, ou perdue par l'issue tirée).
	_place(dm, Dieverting, Vector3i(1, 0, 5))
	_place(dm, Dieverting, Vector3i(1, 0, 7))
	GameSession.add_object(&"spade", 1)  # de quoi détruire UN dé
	# Sortie au fond du couloir : de quoi distinguer « renvoyé à l'entrée » de « renvoyé à une
	# sortie » (l'entrée, elle, est déclarée par `exploration.gd` sur la case de départ).
	dm.add_exit(Vector3i(1, 0, 8))
	AbilityCatalog.dev_granted = [&"fog_mantel"]  # pour voir le cristal rafraîchir
	GameSession.mark_exploration_ability_used(&"fog_mantel")
	return Vector3i(1, 0, 0)


static func _walls(dm) -> Vector3i:
	# Deux zones séparées par une rangée de murs en z=3, percée d'un mur fissuré en (1,0,3).
	_floor_rect(dm, 0, 0, 3, 3)  # z 0..2
	_floor_rect(dm, 0, 4, 3, 3)  # z 4..6
	_place(dm, CrackedWall, Vector3i(1, 0, 3))
	_place(
		dm, ExaminableDecor, Vector3i(0, 0, 1), {"decor_type": ExaminableDecor.DecorType.POSTERS}
	)
	AbilityCatalog.dev_granted = [&"cranny_crossing"]
	return Vector3i(1, 0, 0)


## Même ravin que [method _bridge], plus un rival sur la plateforme de départ : il te suit
## sur la planche. Sert à éprouver les règles « rivaux » de la doc (test d'équilibre simplifié,
## croisement = double chute, poursuite par la chute).
static func _bridge_rival(dm) -> Vector3i:
	# Sans piège disarray : ici on éprouve les règles « rivaux », pas l'inertie de commande.
	var start := _build_bridge_map(dm, false)
	# Rival posé DE L'AUTRE CÔTÉ du ravin : il doit emprunter le pont pour t'atteindre, donc
	# la rencontre a forcément lieu SUR une planche. Côté départ, il te rattrapait avant même
	# que tu t'engages et on ne testait qu'un contact ordinaire.
	_spawn_rival(dm, &"ravbak", Vector3i(1, 2, 7))
	return start


static func _bridge(dm) -> Vector3i:
	return _build_bridge_map(dm)


## Géométrie commune aux deux scénarios de pont. `disarray_trap` pose (ou non) le piège de la
## case d'arrivée : utile pour tester le retour sous disarray, parasite pour tester les rivaux.
static func _build_bridge_map(dm, disarray_trap: bool = true) -> Vector3i:
	# Ravin à DEUX étages de profondeur, enjambé par un tronc étroit. Tomber du pont n'est pas
	# un « retour au départ » : on atterrit au FOND (dégâts de chute normaux, ∝ profondeur) et
	# on remonte par deux volées d'escalier côté x = 3.
	#
	#   y = 2  plateformes + pont      y = 1  corniche de retour      y = 0  fond du ravin
	_floor_rect_y(dm, 0, 0, 3, 2, 2)  # plateforme de départ  x 0..2, z 0..1
	dm.add_floor(Vector3i(3, 2, 0))  # palier haut de la 2e volée
	dm.add_floor(Vector3i(1, 2, 7))  # arrivée : UNE case, murée sur 3 côtés par render_grid
	# (le pont est la seule issue → on repart forcément
	# dessus, sans gaspiller de mouvements de disarray)
	# Le pont : chaque case porte le mécanisme (s'engage dans le sens du regard, deux sens) ;
	# praticable mais « fosse » — seule la planche la tient, le ravin s'ouvre dessous.
	for z in range(2, 7):
		var c := Vector3i(1, 2, z)
		dm.add_floor(c)
		dm.mark_pit(c)
		_spawn_plank(dm, c)
		_place(dm, NarrowBridge, c)
	# Fond du ravin (2 étages plus bas) : reçoit la chute sur toute la longueur du pont.
	_floor_rect_y(dm, 0, 2, 4, 5, 0)  # x 0..3, z 2..6
	dm._floor.erase(Vector3i(3, 0, 4))  # cage de la 1re volée (on n'atterrit pas SUR l'escalier)
	# Corniche intermédiaire reliant les deux volées.
	dm.add_floor(Vector3i(3, 1, 2))
	dm.add_floor(Vector3i(3, 1, 3))
	# Remontée : fond → corniche, puis corniche → plateforme de DÉPART (on ne gagne pas la
	# traversée en tombant). Chaque volée = une case montante + sa case descendante au-dessus.
	_place(dm, Stairs, Vector3i(3, 0, 4), {"level_delta": 1, "face_dir": Vector3i(0, 0, -1)})
	_place(dm, Stairs, Vector3i(3, 1, 4), {"level_delta": -1, "face_dir": Vector3i(0, 0, 1)})
	_place(dm, Stairs, Vector3i(3, 1, 1), {"level_delta": 1, "face_dir": Vector3i(0, 0, -1)})
	_place(dm, Stairs, Vector3i(3, 2, 1), {"level_delta": -1, "face_dir": Vector3i(0, 0, 1)})
	# Piège disarray sur la case d'ARRIVÉE : il s'arme tout seul en sortant du pont, donc
	# l'aller se teste en état normal et le retour sous disarray (inertie de commande +25 %).
	# Durée relevée à 6-8 mouvements pour CE test (doc : 3-5) : faire demi-tour coûte déjà
	# 2 mouvements et le pas sur la planche un 3e — à 3-5 la traversée retour serait à pile ou
	# face déjà purgée du disarray. À 6-8 il en reste 3-5 pour le pont, qui les décompte case
	# par case (on voit le compteur du HUD descendre pendant la traversée).
	if disarray_trap:
		_place(
			dm,
			Trap,
			Vector3i(1, 2, 7),
			{"kind": Trap.Kind.DISARRAY, "revealed": true, "disarray_min": 6, "disarray_max": 8}
		)
	return Vector3i(1, 2, 0)


## Planche du pont : boîte brune étroite orientée dans le sens de la traversée, sa face haute
## au niveau du sol de la case (que la fosse, elle, a laissé vide).
static func _spawn_plank(dm, cell: Vector3i) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.35, 0.1, dm.CELL_SIZE)
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.52, 0.38, 0.24)
	mi.material_override = mat
	mi.position = dm.cell_to_world(cell) + Vector3(0.0, -0.05, 0.0)
	dm.add_child(mi)


static func _stairs(dm) -> Vector3i:
	# Pyramide à CINQ gradins, pour éprouver tout le barème de chute de la doc (1 unité = 0
	# dégât, 2 = 10, 3 = 15, 4 = 20) et les deux formes d'ascenseur.
	#
	#   étage 0 : x 0..7, z 0..12      (salle d'accès, passe SOUS tous les gradins)
	#   étage 1 : x 1..6, z 4..12
	#   étage 2 : x 2..6, z 4..12
	#   étage 3 : x 3..6, z 4..12
	#   étage 4 : x 4..6, z 4..12
	#
	# Colonne EST (x = 7) : rien n'arrête la chute avant l'étage 0 — en sortir depuis les gradins
	# 1/2/3/4 coûte 1/2/3/4 unités, soit 0/10/15/20 DEN. Côté OUEST, chaque gradin surplombe le
	# suivant : une seule unité, donc indolore.
	_floor_rect_y(dm, 0, 0, 8, 13, 0)
	_floor_rect_y(dm, 1, 4, 6, 9, 1)
	_floor_rect_y(dm, 2, 4, 5, 9, 2)
	_floor_rect_y(dm, 3, 4, 4, 9, 3)
	_floor_rect_y(dm, 4, 4, 3, 9, 4)

	# PILIER : on retire une case de l'étage 0 sous le gradin 1 — elle devient un bloc de mur,
	# et c'est SA face haute qui sert de sol à la case du dessus (doc « Walls + Decors » : un mur
	# peut servir de sol à l'étage au-dessus, ce qui évite d'empiler mur + dalle).
	dm._floor.erase(Vector3i(1, 0, 8))

	# RAMBARDES : le bord est du gradin du haut n'est protégé que sur ses deux premières cases.
	# Deux pas plus loin, le même bord est ouvert et coûte une chute de 4 unités — de quoi
	# comparer les deux à un pas d'intervalle.
	for z in [4, 5]:
		_place(dm, Guardrail, Vector3i(6, 4, z), {"edge_dir": Vector3i(1, 0, 0)})

	# UN ESCALIER PAR PALIER, en quinconce vers +z. C'est le chemin toujours praticable : un
	# ascenseur reste où on l'a laissé (doc : il faut remonter dessus pour le rappeler), donc
	# sans ces volées, tomber d'un étage desservi par le seul ascenseur rendrait le haut
	# définitivement inaccessible.
	for flight in [Vector3i(1, 0, 4), Vector3i(2, 1, 6), Vector3i(3, 2, 8), Vector3i(4, 3, 10)]:
		var up: Vector3i = flight
		var down: Vector3i = up + Vector3i(0, 1, 0)
		dm._floor.erase(up)  # une case de volée n'est pas praticable : on est porté au-delà
		dm._floor.erase(down)
		_place(dm, Stairs, up, {"level_delta": 1, "face_dir": Vector3i(0, 0, 1)})
		_place(dm, Stairs, down, {"level_delta": -1, "face_dir": Vector3i(0, 0, -1)})

	# Les ascenseurs sont des RACCOURCIS, doublés par les escaliers ci-dessus.
	# `path` est un Array[Vector3i] TYPÉ : lui passer une Array non typée via `set()` échouerait
	# en silence (le mécanisme se retrouverait sans trajet).
	# 1 <-> 2 : trajet VERTICAL tout simple (un seul point de passage).
	var straight: Array[Vector3i] = [Vector3i(6, 2, 12)]
	_place(dm, Elevator, Vector3i(6, 1, 12), {"path": straight})
	# 3 <-> 4 : trajet COMPLEXE, qui sort au-dessus du vide et enchaîne des segments sur les
	# trois axes (+x, +z, +y, -x) avant de se poser sur le gradin du haut.
	var winding: Array[Vector3i] = [
		Vector3i(7, 3, 5), Vector3i(7, 3, 12), Vector3i(7, 4, 12), Vector3i(6, 4, 12)
	]
	_place(dm, Elevator, Vector3i(6, 3, 5), {"path": winding})
	return Vector3i(3, 0, 0)


static func _abilities(dm) -> Vector3i:
	_floor_rect(dm, 0, 0, 3, 10)
	# Capacités accordées + objets d'exploration dans l'inventaire.
	AbilityCatalog.dev_granted = [&"fog_mantel", &"static_camouflage"]
	GameSession.add_object(&"tea_drop", 1)
	GameSession.add_object(&"rune_stone", 2)
	GameSession.add_object(&"torment_veil", 1)
	GameSession.add_object(&"smoke_bomb", 1)  # doit rester indisponible en explo
	# Un piège de poison pour tester tea_drop, et un rival qui chasse pour tester fog/veil.
	_place(dm, Trap, Vector3i(1, 0, 2), {"kind": Trap.Kind.POISON, "revealed": true})
	_spawn_rival(dm, &"ravbak", Vector3i(1, 0, 8))
	return Vector3i(1, 0, 0)
