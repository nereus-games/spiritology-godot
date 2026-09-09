## Rival sur la grille du donjon (sprite billboard). Agit à chaque tour du joueur.
##
## Comportement (porté du proto, sur grille logique) : chasse le joueur quand il est en
## vue, garde une mémoire de sa dernière position connue quelques tours, sinon erre au
## hasard. Entrer sur la case du joueur (ou inversement) déclenche une rencontre.
## Réagit aux tours via [method take_turn], appelé par le [DungeonManager].
class_name RivalBehavior
extends Node3D

const AfflictionState := preload("res://scripts/exploration/mechanisms/affliction_state.gd")

@export var species_id := &"ravbak"      ## espèce du rival (pour bâtir la rencontre)
@export var vision_range := 5            ## portée de détection, en cases (Manhattan)
@export var turns_between_actions := 1   ## 1 = agit chaque tour, 2 = un tour sur deux…
@export var memory_turns := 2            ## tours de mémoire après perte de vue
@export var move_duration := 0.18
## Encombrement maximal du sprite, en mètres : il tient dans un carré de ce côté (charte
## « Visuals + Sounds » : rival sprites max 90 cm × 90 cm). Une case fait
## [constant DungeonManager.CELL_SIZE] (1 m), donc 0.9 = une créature qui remplit presque sa
## case sans jamais déborder sur les voisines, quelle que soit la forme du dessin.
@export var world_height := 0.9

## DEN maximal du rival, ATTRIBUÉ PAR LE LEVEL DESIGN donjon par donjon. Les ordres de
## grandeur visés sont ceux de la doc (cf. [constant GameSession.RIVAL_DEN_EARLY] / _MID /
## _LATE), mais rien n'oblige à s'y tenir exactement : c'est un réglage de donjon.
@export var max_den := GameSession.RIVAL_DEN_EARLY

## Probabilité de tomber PAR CASE de pont étroit franchie (doc : « a simple probability to
## fall of 1 to 2 % — exact percentage is generated along with the rival »). 0 = à tirer.
@export var bridge_fall_chance := 0.0

## Envie de poursuivre par une chute quand celle-ci ne coûte RIEN (doc : « a rival may decide
## to fall to pursue the player »). Le tirage est refait à chaque occasion, mais pondéré par ce
## que la chute coûterait — cf. [method fall_pursuit_chance]. Ne concerne que la chute : un
## escalier ou un ascenseur, gratuits, sont empruntés sans hésiter.
@export var pursue_fall_chance := 0.5

## Exposant de prudence : plus il est haut, plus le rival renâcle dès que la chute entame une
## part sensible de sa densité. 1 = arbitrage linéaire, 2 = nettement plus prudent.
@export var fall_prudence := 2.0

## Tours pendant lesquels un rival poursuit le joueur après l'avoir vu changer d'étage. Plus
## long que [member memory_turns] : rejoindre un escalier prend des tours, alors que la mémoire
## ordinaire ne sert qu'à ne pas perdre une piste toute fraîche.
##
## TODO (2026-09-02) : valeur JAMAIS éprouvée en jeu, et l'expiration elle-même n'est pas dans la
## doc Notion — délibérément, tant qu'on ne l'a pas testée. À reprendre dans la passe de réglage
## des poursuites, puis à écrire dans « Game Design / Gameplay Elements / Rivals ».
@export var level_pursuit_turns := 8

var cell: Vector3i
var _dungeon: DungeonManager
var _busy := false

## DEN courant SUR LA CARTE (jamais affiché). Les chutes l'entament ; il est reporté dans la
## rencontre qui suit, et un rival tombé à 0 est dissous sur place, sans rencontre.
var den := 0

## Poursuite à travers les étages : case où le joueur a été vu arriver, et tours restants.
var _level_target: Vector3i
var _level_pursuit := 0

## Effets persistants subis par le rival (poison, disarray), lus par les pièges. Le poison
## n'a pas de cible DEN sur la carte (le DEN vit dans la rencontre) : il est décompté ici et
## sera repris à l'ouverture d'une rencontre quand ce câblage existera.
var affliction := AfflictionState.new()

var _has_target := false
var _target_cell: Vector3i
var _memory := 0
var _cooldown := 0

func _ready() -> void:
	_fit_sprite()
	den = max_den
	# « exact percentage is generated along with the rival » : chaque rival a sa propre
	# sûreté de pied, tirée une fois pour toutes dans la fourchette de la doc.
	if bridge_fall_chance <= 0.0:
		bridge_fall_chance = randf_range(0.01, 0.02)
	_dungeon = get_tree().get_first_node_in_group("dungeon") as DungeonManager
	if _dungeon == null:
		push_error("[RivalBehavior] aucun DungeonManager dans le groupe 'dungeon'.")
		return
	cell = _dungeon.world_to_cell(global_position)
	global_position = _dungeon.cell_to_world(cell)
	_dungeon.register_rival(self)

## Fait tenir le sprite dans un carré de [member world_height] de côté, quelle que soit la
## résolution ET LES PROPORTIONS du PNG.
##
## Indispensable : les sources vont de 800x800 à 2341x3500 px. Avec un `pixel_size`
## figé dans la scène, chaque espèce sortirait à une taille différente — à 0.02, ravbak
## faisait 16 unités de haut et fliritus en ferait 70. On dérive donc
## `pixel_size` de la hauteur voulue au lieu de le subir de la résolution.
##
## À NE PAS repasser en billboard PLEIN (`billboard = 1`) dans `rival.tscn` : un billboard
## plein s'aligne sur TOUS les axes de la caméra, roulis compris. Pendant un test d'équilibre,
## la caméra roule avec le déséquilibre du joueur — et tous les rivaux visibles penchaient
## avec lui. Le mode Y-fixe (`billboard = 2`) ne les fait pivoter qu'autour de la verticale.
func _fit_sprite() -> void:
	var sprite := get_node_or_null("Sprite3D") as Sprite3D
	if sprite == null or sprite.texture == null:
		return
	var tex_height := sprite.texture.get_height()
	var tex_width := sprite.texture.get_width()
	if tex_height <= 0 or tex_width <= 0:
		return
	# On cale sur le plus GRAND côté : caler sur la hauteur seule laisserait un dessin plus large
	# que haut (jézal, 2000 × 1898) déborder de la case en largeur.
	sprite.pixel_size = world_height / float(maxi(tex_width, tex_height))
	# Le quad est centré sur son origine : on le remonte d'une demi-hauteur RÉELLE pour qu'il
	# pose sur le sol de la case au lieu d'être à moitié enterré (ou de flotter).
	sprite.position.y = tex_height * sprite.pixel_size * 0.5

## Joué par le DungeonManager à chaque tour, avec la case courante du joueur.
func take_turn(player_cell: Vector3i) -> void:
	if _busy or _dungeon == null:
		return
	if _cooldown > 0:
		_cooldown -= 1
		return
	_cooldown = turns_between_actions - 1

	# Poursuite à travers les étages. Aucune vision inter-étages n'est requise : le rival a VU
	# le joueur partir et se souvient d'où il est allé.
	var pursuing_level := _level_pursuit > 0
	if pursuing_level:
		_level_pursuit -= 1
		if cell.y == _level_target.y:
			pursuing_level = false  # même étage : la chasse ordinaire reprend la main
			_level_pursuit = 0
			_target_cell = _level_target
			_has_target = true
			_memory = memory_turns
		elif await _pursue_level():
			return  # l'action du tour a été consommée (chute ou escalier)
	if not pursuing_level:
		_update_memory(player_cell)

	var delta := _chase_dir(_target_cell) if _has_target else _random_dir()
	# Disarray : une part des mouvements du rival est déviée au hasard.
	if affliction.consume_move():
		delta = _random_dir()
	var next := cell + delta

	# Une porte fermée barre aussi le rival (et le contact au travers).
	if _dungeon.is_edge_blocked(cell, next):
		return

	# Escalier devant, abordé dans son axe : le rival l'emprunte comme le joueur (porté 2 cases
	# plus loin + changement d'étage). Dans le mauvais sens, il bloque comme un mur.
	var stairs := _stairs_at(next)
	if stairs != null:
		if delta == stairs.face_dir:
			await _use_level_link(stairs)
		return

	# Sur une planche, un croisement ne se règle pas par un contact : les deux tombent (doc).
	if _dungeon.is_narrow_bridge(next):
		if next == player_cell:
			_dungeon.request_bridge_collision(self, next)
			return
		var occupant := _dungeon.occupant_at(next)
		if occupant != null and occupant != self:
			_collide_with_rival(next, occupant)
			return
	elif next == player_cell:
		_dungeon.request_encounter(self, true)  # contact : rencontre, pas de déplacement
		return

	if _dungeon.move_occupant(cell, next, self):
		await _step_to(next)
		if _dungeon == null:
			return  # dissous entre-temps
		_dungeon.notify_entered(next, self)  # pièges de la case atteinte
		# Test d'équilibre du rival : une planche franchie = une chance de tomber. Version
		# simplifiée du test temps réel du joueur (doc : « a similar test […] a simple
		# probability to fall »).
		if _dungeon.is_narrow_bridge(cell) and randf() < bridge_fall_chance:
			fall_down(cell)

func _update_memory(player_cell: Vector3i) -> void:
	if _can_see(player_cell):
		_target_cell = player_cell
		_has_target = true
		_memory = memory_turns
	elif _memory > 0:
		_memory -= 1
	else:
		_has_target = false

## Vue simple : portée Manhattan, SANS occlusion.
##
## ## TODO(doc « Game Design / Dungeon Exploration ») : la doc est désormais explicite — « the
## line of sight is blocked by walls » (les personnages sont petits, yeux à
## [constant DungeonManager.EYE_HEIGHT] = 60 cm). Un rival voit donc aujourd'hui à travers les
## murs, ce qui n'est plus conforme. De quoi le faire : tracer les cases entre le rival et le
## joueur et couper la vue à la première arête opaque ([method DungeonManager.is_edge_opaque])
## ou case non praticable. À reprendre avec de vrais donjons, où l'occlusion compte vraiment.
func _can_see(player_cell: Vector3i) -> bool:
	# Discrétion du joueur (fog mantel, torment veil, costume) : indétectable.
	if _dungeon != null and _dungeon.rivals_ignore_player():
		return false
	if player_cell.y != cell.y:
		return false
	var d: Vector3i = (player_cell - cell).abs()
	return d.x + d.z <= vision_range

func _chase_dir(target: Vector3i) -> Vector3i:
	var diff := target - cell
	if absi(diff.x) > absi(diff.z):
		return Vector3i(signi(diff.x), 0, 0)
	return Vector3i(0, 0, signi(diff.z))

func _random_dir() -> Vector3i:
	match randi() % 4:
		0: return Vector3i(1, 0, 0)
		1: return Vector3i(-1, 0, 0)
		2: return Vector3i(0, 0, 1)
		_: return Vector3i(0, 0, -1)

func _step_to(next: Vector3i) -> void:
	cell = next
	_busy = true
	var tween := create_tween()
	tween.tween_property(self, "global_position", _dungeon.cell_to_world(next), move_duration)
	await tween.finished
	_busy = false

## Relocalisation instantanée sur une case (piège de téléportation). L'occupation est gérée
## par [method DungeonManager.teleport_actor].
func teleport_to(to_cell: Vector3i) -> void:
	cell = to_cell
	global_position = _dungeon.cell_to_world(to_cell)

# --------------------------------------------------------------------------
# Ponts étroits : chute, croisements, DEN de carte
# --------------------------------------------------------------------------

## Le joueur vient de changer d'étage sous les yeux du rival (chute, escalier, ascenseur…) :
## celui-ci retient OÙ il est allé et le poursuit par ses propres moyens (cf. [method
## _pursue_level]). Aucune vision inter-étages n'est requise : c'est le DÉPART qui est vu.
func witness_player_level_change(from_cell: Vector3i, to_cell: Vector3i) -> void:
	if not _can_see(from_cell):
		return
	_level_target = to_cell
	_level_pursuit = level_pursuit_turns

## Un tour de poursuite vers l'étage du joueur. Retourne true si l'action du tour est
## consommée (le rival a sauté ou pris un escalier) ; false s'il lui reste à se déplacer,
## auquel cas la case visée a été posée sur l'escalier à rejoindre.
##
## Deux moyens, et un seul est gratuit : l'escalier s'emprunte sans hésiter, tandis que se
## jeter dans le vide coûte du DEN — d'où le tirage sur [member pursue_fall_chance], qui
## traduit le « may decide » de la doc.
func _pursue_level() -> bool:
	var going_down: bool = _level_target.y < cell.y
	if going_down:
		# On ne se jette pas dans le vide depuis n'importe où : il faut un BORD ouvert à
		# enjamber. Une rambarde (ou une porte fermée) sur ce bord retient donc le rival comme
		# elle retient le joueur.
		var brink := _open_drop_edge(_level_target)
		if brink != cell:
			var landing: Vector3i = _dungeon.fall_landing(brink)
			# Ne sauter que si ça rapproche vraiment (ne pas dépasser l'étage visé).
			if landing.y >= _level_target.y:
				if randf() >= fall_pursuit_chance(cell.y - landing.y):
					return false  # il renonce ce tour-ci
				fall_down(brink)
				return true
	var link := _nearest_level_link(-1 if going_down else 1)
	if link == null:
		return false  # aucun moyen d'atteindre cet étage : il se déplacera au hasard
	var approach: Vector3i = link.level_link_from()
	if cell == approach:
		# Escalier : il faut encore entrer dedans. Ascenseur : être monté dessus a déjà tout
		# déclenché, il n'y a rien à faire de plus.
		if link.level_link_needs_step_in():
			return await _use_level_link(link)
		return false
	_target_cell = approach
	_has_target = true
	return false

## Bord ouvert le plus prometteur pour sauter vers `toward` : case voisine dans le vide, dont
## l'arête n'est barrée par rien (une RAMBARDE la protège comme elle protège le joueur) et sous
## laquelle il y a un sol. Retourne la case courante si aucun bord ne convient — le rival reste
## alors sur son étage. Un trou sans fond n'est jamais choisi : on ne s'y jette pas volontairement.
func _open_drop_edge(toward: Vector3i) -> Vector3i:
	var best := cell
	var best_score := 1 << 30
	for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		var n: Vector3i = cell + d
		if _dungeon.is_edge_blocked(cell, n) or _dungeon.is_floor(n):
			continue
		var landing: Vector3i = _dungeon.fall_landing(n)
		if landing == n:
			continue  # mur plein, ou trou sans fond
		var score: int = absi(landing.x - toward.x) + absi(landing.z - toward.z)
		if score < best_score:
			best_score = score
			best = n
	return best

## Chance, CE TOUR-CI, de se jeter dans le vide pour poursuivre, une fois pesé ce que la chute
## coûterait. Le tirage étant refait à chaque occasion, c'est cette pondération qui empêche la
## poursuite d'être une quasi-certitude dès qu'on laisse passer quelques tours.
##
## Trois régimes : une chute indolore (1 unité de hauteur) ne retient personne ; une chute qui
## le dévitaliserait est TOUJOURS refusée (un rival ne se suicide pas pour une poursuite, et ça
## offrirait au joueur une élimination gratuite) ; entre les deux, l'envie décroît avec la part
## de sa densité restante que la chute lui coûterait.
func fall_pursuit_chance(levels: int) -> float:
	var damage := DungeonManager.fall_damage(levels)
	if damage <= 0:
		return pursue_fall_chance
	if damage >= den:
		return 0.0
	var risk := float(damage) / float(den)
	return pursue_fall_chance * pow(1.0 - risk, fall_prudence)

## Passage vers un autre étage le plus proche (distance de Manhattan) allant dans le sens voulu,
## abordable depuis l'étage du rival. `direction` = +1 pour monter, -1 pour descendre.
##
## Générique : escalier, ascenseur, ou tout mécanisme futur qui implémente l'interface de
## changement d'étage de [DungeonMechanism].
func _nearest_level_link(direction: int) -> Node:
	var best: Node = null
	var best_dist := 1 << 30
	for m in _dungeon.get_children():
		if not m.has_method("has_level_link") or not m.has_level_link():
			continue
		var from: Vector3i = m.level_link_from()
		var to: Vector3i = m.level_link_to()
		if from.y != cell.y or signi(to.y - from.y) != direction:
			continue
		if not _dungeon.is_floor(from):
			continue
		var d: Vector3i = (from - cell).abs()
		var dist: int = d.x + d.z
		if dist < best_dist:
			best_dist = dist
			best = m
	return best

## Mécanisme d'escalier posé sur la case `c`, ou null.
func _stairs_at(c: Vector3i) -> Node:
	for m in _dungeon.mechanisms_at(c):
		if m.has_method("stairs_destination"):
			return m
	return null

## Emprunte le passage `link` depuis la case courante (escalier à gravir, etc.). Retourne
## false si l'arrivée n'est pas praticable ou est occupée.
func _use_level_link(link) -> bool:
	var dest: Vector3i = link.level_link_to()
	if not _dungeon.is_floor(dest) or _dungeon.occupant_at(dest) != null:
		return false
	_dungeon.release(cell)
	_dungeon.reserve(dest, self)
	await _step_to(dest)
	if _dungeon == null:
		return true  # dissous entre-temps
	_dungeon.notify_entered(dest, self)
	return true

## Chute volontaire ou subie depuis `from_cell` : atterrit sur le sol en contrebas et encaisse
## les dégâts. Retourne false si le rival en est dévitalisé (donc dissous).
func fall_down(from_cell: Vector3i) -> bool:
	var landing: Vector3i = _dungeon.fall_landing(from_cell)
	if landing == from_cell:
		# Trou franc sans fond (erreur de level design) : le rival y disparaît, comme le duo y
		# serait dévitalisé. Sinon, rien en dessous = pas de chute possible.
		if _dungeon.is_bottomless(from_cell):
			queue_free()
			return false
		return true
	return drop_to(landing, from_cell.y - landing.y)

## Pose le rival sur `target` au terme d'une chute de `levels` étages et lui applique les
## dégâts. Si `target` est occupée, il atterrit sur la case libre la plus proche : l'invariant
## « un occupant par case » tient toute la grille, on ne l'assouplit pas pour une chute.
## Retourne false s'il est dévitalisé par la chute.
func drop_to(target: Vector3i, levels: int) -> bool:
	var dest: Vector3i = _dungeon.free_cell_near(target)
	_dungeon.release(cell)
	_dungeon.reserve(dest, self)
	cell = dest
	# La case change tout de suite (l'appelant a besoin du résultat dans le tour courant), mais
	# la descente est ANIMÉE : sans ça le rival disparaît de la planche et réapparaît en bas,
	# et on ne voit jamais qu'il est tombé.
	_busy = true
	var tween := create_tween()
	tween.tween_property(self, "global_position", _dungeon.cell_to_world(dest), 0.35)
	tween.finished.connect(func() -> void: _busy = false)
	if not apply_map_damage(DungeonManager.fall_damage(levels)):
		return false
	_dungeon.notify_entered(dest, self)
	return true

## Applique des dégâts subis SUR LA CARTE (chute). Le DEN restant est reporté dans la
## rencontre qui suit ; s'il tombe à 0, le rival est dévitalisé sur place et dissous, SANS
## rencontre (doc). Retourne true si le rival survit.
##
## Une dévitalisation SUR LA CARTE ne compte PAS comme une dévitalisation de rencontre :
## elle n'alimente donc ni le compteur FDE ni le PSY (décision de design, 2026-08-12).
## `GameSession.register_encounter_end` n'est volontairement pas appelé ici.
func apply_map_damage(amount: int) -> bool:
	den = maxi(den - amount, 0)
	if den > 0:
		return true
	_dissolve()
	return false

## Dévitalisé hors rencontre : le rival quitte la grille.
func _dissolve() -> void:
	_dungeon.release(cell)
	_dungeon.unregister_rival(self)
	_dungeon = null  # empêche _exit_tree de re-désenregistrer
	queue_free()

## Deux rivaux se croisent sur une planche : les deux tombent, l'occupant sur la case du
## dessous, l'arrivant sur une case adjacente (doc).
func _collide_with_rival(tile: Vector3i, other: Node) -> void:
	var landing: Vector3i = _dungeon.fall_landing(tile)
	if landing == tile:
		return  # aucun vide sous cette planche : personne ne tombe
	var levels: int = tile.y - landing.y
	if other.has_method("drop_to"):
		other.drop_to(landing, levels)
	drop_to(_dungeon.free_cell_near(landing), levels)

## Fin de tour : fait s'écouler le poison. Pas de DEN sur la carte pour un rival → l'effet
## est simplement décompté (l'état sera transféré à la rencontre plus tard).
func on_turn_elapsed() -> void:
	affliction.tick_poison()

func _exit_tree() -> void:
	if _dungeon:
		_dungeon.release(cell)
		_dungeon.unregister_rival(self)
