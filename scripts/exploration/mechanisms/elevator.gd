## Ascenseur : plateforme qui se met en marche dès qu'on pose le pied dessus, parcourt son
## trajet prédéfini en UN tour, et qu'on ramène à son point de départ en y remontant une
## seconde fois (doc Notion, Level Design / Mechanisms « Elevators »).
##
## Le trajet est une SUITE DE POINTS DE PASSAGE en cases absolues ([member path]) : la doc dit
## « a predefined path », sans le restreindre à la verticale. Un ascenseur peut donc monter tout
## droit, glisser à l'horizontale, ou enchaîner des segments sur les trois axes. Seuls comptent
## logiquement les DEUX BOUTS (départ et dernier point) ; les points intermédiaires ne servent
## qu'à dessiner la trajectoire, et peuvent survoler le vide.
##
## La plateforme se déplace VRAIMENT : sa case change, donc elle se réenregistre auprès du
## [DungeonManager] à chaque trajet. Les deux BOUTS doivent être des cases de SOL — ce mécanisme
## ne creuse pas de trou derrière lui, la cage d'ascenseur est affaire de level design.
##
## Le trajet ne coûte pas de tour supplémentaire : le pas qui amène sur la plateforme en a déjà
## consommé un, et la doc précise que le trajet tient « in one turn ».
##
## Pas de `class_name` : `extends` par chemin.
extends "res://scripts/exploration/mechanisms/dungeon_mechanism.gd"

## Points de passage APRÈS la case de départ, en cases ABSOLUES. Le dernier est l'autre bout du
## trajet et doit être du sol. Un seul point = trajet direct (ex. purement vertical).
@export var path: Array[Vector3i] = []

## Durée d'UN segment de trajet, vu de l'extérieur (plateforme vide, ou rival dessus).
## Par segment et non pour le trajet entier : un trajet compliqué doit prendre plus de temps
## qu'un aller vertical, sinon il défile d'autant plus vite qu'il a de choses à montrer.
@export var segment_duration := 0.5

## Durée d'UN segment quand c'est LE JOUEUR qui est à bord. Nettement plus lente : de
## l'extérieur on ne fait que constater qu'une plateforme se déplace, mais à bord on lit le
## trajet — et sur un chemin qui part de côté puis remonte, il faut le temps de voir où il mène.
@export var rider_segment_duration := 1.2

var _origin: Vector3i
var _at_far_end := false
var _moving := false

func _on_registered() -> void:
	_origin = cell
	if path.is_empty():
		push_warning("[Elevator] en %s : aucun trajet renseigné." % cell)

## Autre bout du trajet : le dernier point de passage à l'aller, la case de départ au retour.
func far_end() -> Vector3i:
	if path.is_empty():
		return cell
	return _origin if _at_far_end else path[path.size() - 1]

## Points à parcourir, dans l'ordre, pour rejoindre l'autre bout depuis la position courante.
func _route() -> Array:
	if path.is_empty():
		return []
	if _at_far_end:
		# Retour : on remonte les points intermédiaires à l'envers, puis on rentre au départ.
		var back: Array = []
		for i in range(path.size() - 2, -1, -1):
			back.append(path[i])
		back.append(_origin)
		return back
	return path.duplicate()

## Poser le pied dessus suffit à l'actionner (doc). Vaut pour le joueur comme pour un rival :
## la doc « Rivals » veut qu'un rival suive le joueur par les moyens sans coût en DEN.
func on_enter(who: Node) -> void:
	ride(who)

## Emmène `who` et la plateforme à l'autre bout. Retourne la case d'arrivée (ou la case
## courante si le trajet n'a pas pu se faire).
func ride(who: Node) -> Vector3i:
	var route := _route()
	if _moving or _dungeon == null or route.is_empty():
		return cell
	var dest: Vector3i = route[route.size() - 1]
	if dest == cell:
		return cell
	if not _dungeon.is_floor(dest):
		push_warning("[Elevator] %s -> %s : l'arrivée n'est pas du sol." % [cell, dest])
		return cell
	var from := cell
	_moving = true
	_dungeon.unregister_mechanism(from, self)
	cell = dest
	_dungeon.register_mechanism(cell, self)
	_at_far_end = not _at_far_end
	# La plateforme et son passager avancent forcément à la MÊME cadence, sinon le passager
	# décollerait ; c'est donc la présence du joueur à bord qui règle la vitesse du tout.
	var per_segment: float = rider_segment_duration if _dungeon.is_player(who) else segment_duration
	_carry(who, from, dest, route, per_segment)
	var tween := _travel_tween(self, route, per_segment)
	tween.finished.connect(func() -> void: _moving = false)
	return dest

## Enchaîne un déplacement le long de `route`, à `per_segment` secondes par point de passage.
func _travel_tween(node: Node3D, route: Array, per_segment: float) -> Tween:
	var tween := node.create_tween()
	for wp in route:
		tween.tween_property(node, "global_position", _dungeon.cell_to_world(wp), per_segment)
	return tween

## Emporte le passager avec la plateforme : sa case change tout de suite (la logique de tour en
## dépend), mais son corps suit la trajectoire au lieu de se téléporter.
func _carry(who: Node, from: Vector3i, dest: Vector3i, route: Array, per_segment: float) -> void:
	if who == null or not who.has_method("teleport_to"):
		return
	# Un rival occupe une case, pas le joueur : l'occupation suit le passager.
	if not _dungeon.is_player(who):
		_dungeon.release(from)
		_dungeon.reserve(dest, who)
	# Les rivaux témoins peuvent décider de suivre (doc « Rivals »).
	_dungeon.notify_level_change(who, from, dest)
	who.teleport_to(dest)
	who.global_position = _dungeon.cell_to_world(from)  # on repart du départ pour l'animation
	var locked: bool = "input_locked" in who
	if locked:
		who.input_locked = true
	var tween := _travel_tween(who, route, per_segment)
	tween.finished.connect(func() -> void:
		if locked and is_instance_valid(who):
			who.input_locked = false)

# --- Changement d'étage (interface commune, cf. DungeonMechanism) ---

## Un ascenseur purement HORIZONTAL ne relie pas deux étages : il ne sert alors à rien pour la
## poursuite d'un rival, qui n'a qu'à marcher.
func has_level_link() -> bool:
	return far_end().y != cell.y

## On emprunte un ascenseur en MONTANT DESSUS : la case d'abord est la plateforme elle-même.
func level_link_from() -> Vector3i:
	return cell

func level_link_to() -> Vector3i:
	return far_end()

## Pas d'entrée « dans » le mécanisme : arriver sur la plateforme suffit ([method on_enter]).
func level_link_needs_step_in() -> bool:
	return false

## Plateforme : dalle épaisse posée au sol de la case, franchement colorée pour la repérer.
func _spawn_visual() -> void:
	_add_marker_box(Color(0.85, 0.62, 0.20), Vector3(0.9, 0.12, 0.9))
