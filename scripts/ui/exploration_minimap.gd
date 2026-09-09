## Mini-map d'exploration (élément 1 du HUD, doc « User Interface »).
##
## Dessine la grille LOGIQUE du donjon vue de dessus : dalles de sol, mécanismes, et la
## position du joueur. Placeholder de test (formes simples), rafraîchi chaque frame. Interroge
## le donjon (groupe "dungeon") et le joueur (groupe "player").
##
## Pas de `class_name` (piège du cache CLI) : référencé par `preload`.
extends Control

## Taille d'une case sur la mini-map (px).
const CELL_PX := 11.0

const FLOOR_COLOR := Color(0.30, 0.30, 0.36)
## Cases d'un étage INFÉRIEUR à celui du joueur : assombries, pour que la limite de l'étage
## où l'on se trouve (bord d'une plateforme, trémie) se lise d'un coup d'œil.
const FLOOR_BELOW_COLOR := Color(0.15, 0.15, 0.19)
## Murs de l'étage courant : plus sombres que le sol mais nettement au-dessus du fond, pour que
## le POURTOUR d'une salle se lise (doc « User Interface » : la carte montre sol + murs).
const WALL_COLOR := Color(0.20, 0.20, 0.25)
const MECH_COLOR := Color(0.90, 0.65, 0.20)
## Mécanisme ÉPUISÉ (piège déclenché, coffre vidé, dé roulé, sol creusé…) : même règle qu'en
## 3D — ce qui n'est plus actionnable ne doit plus attirer l'œil comme une piste à suivre.
## Il reste dessiné (repère de navigation, et la doc demande explicitement une icône sur la
## carte pour un sol friable déjà creusé), mais éteint.
const MECH_SPENT_COLOR := Color(0.38, 0.33, 0.26)
const PLAYER_COLOR := Color(0.40, 0.90, 0.55)
const BG_COLOR := Color(0.05, 0.05, 0.07, 0.6)

var _dungeon
var _player

func _ready() -> void:
	custom_minimum_size = Vector2(170, 170)
	clip_contents = true  # un grand donjon ne doit pas déborder sur le reste du HUD

func _process(_delta: float) -> void:
	if _dungeon == null:
		_dungeon = get_tree().get_first_node_in_group("dungeon")
	if _player == null:
		_player = get_tree().get_first_node_in_group("player")
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG_COLOR)
	if _dungeon == null:
		return
	var floors: Array = _dungeon._floor.keys()
	if floors.is_empty():
		return
	# Bornes de la grille : sols ET murs, sinon le pourtour se dessinerait hors du cadre.
	var minx: int = floors[0].x
	var minz: int = floors[0].z
	var maxx: int = minx
	var maxz: int = minz
	for c in floors + _dungeon.wall_cells().keys():
		minx = mini(minx, c.x)
		minz = mini(minz, c.z)
		maxx = maxi(maxx, c.x)
		maxz = maxi(maxz, c.z)
	var grid := Vector2((maxx - minx + 1) * CELL_PX, (maxz - minz + 1) * CELL_PX)
	var origin := (size - grid) * 0.5

	# Étage courant du joueur : ce qui est en dessous est assombri, ce qui est au-dessus n'est
	# pas cartographié (on ne voit pas à travers un plafond).
	var level: int = _player.cell.y if is_instance_valid(_player) else 0
	# Dalles de sol : les étages inférieurs d'abord, l'étage courant par-dessus.
	for c in floors:
		if c.y < level:
			draw_rect(Rect2(_cell_px(c, origin, maxx, maxz), Vector2(CELL_PX - 1.0, CELL_PX - 1.0)), FLOOR_BELOW_COLOR)
	for c in floors:
		if c.y == level:
			draw_rect(Rect2(_cell_px(c, origin, maxx, maxz), Vector2(CELL_PX - 1.0, CELL_PX - 1.0)), FLOOR_COLOR)
	# Murs de l'étage courant, par-dessus les sols (un mur peut porter le sol de l'étage du
	# dessus : à cet étage-ci, c'est un mur qu'on doit voir).
	for w in _dungeon.wall_cells():
		if w.y == level:
			draw_rect(Rect2(_cell_px(w, origin, maxx, maxz), Vector2(CELL_PX - 1.0, CELL_PX - 1.0)), WALL_COLOR)
	# Mécanismes de l'étage courant : sur une case (pavé plein) ou sur une arête entre deux
	# cases (barre fine, pour les portes — elles n'occupent aucune case).
	for m in get_tree().get_nodes_in_group("dungeon_mechanism"):
		if not is_instance_valid(m) or m.cell.y != level or not m.shows_on_map():
			continue  # un piège inconnu ne se trahit pas sur la carte
		# Un mécanisme peut imposer sa teinte (rambarde : gris de décor, puisqu'on ne l'actionne
		# pas) ; sinon l'orange des mécanismes interactifs, grisé une fois épuisés.
		var color: Color = MECH_SPENT_COLOR if m.is_spent() else MECH_COLOR
		if m.has_method("map_color"):
			color = m.map_color()
		var edge = m.get("edge_dir")
		if edge != null:
			_draw_edge_mech(m.cell, edge, origin, maxx, maxz, color)
		else:
			draw_rect(Rect2(_cell_px(m.cell, origin, maxx, maxz), Vector2(CELL_PX - 1.0, CELL_PX - 1.0)), color)
	# Joueur : flèche orientée dans le sens du regard.
	if is_instance_valid(_player):
		var p := _cell_px(_player.cell, origin, maxx, maxz) + Vector2(CELL_PX, CELL_PX) * 0.5
		_draw_player_arrow(p)

## Case -> pixel. La carte est tournée de 180° (axes inversés) pour que la position de départ
## soit EN BAS et l'avant du donjon (+z) VERS LE HAUT, avec gauche/droite cohérents avec le
## déplacement.
func _cell_px(c: Vector3i, origin: Vector2, maxx: int, maxz: int) -> Vector2:
	return origin + Vector2((maxx - c.x) * CELL_PX, (maxz - c.z) * CELL_PX)

## Mécanisme d'arête (porte) : barre fine sur la frontière entre `cell` et `cell + edge_dir`,
## posée du côté qui correspond à l'inversion d'axes de la carte.
func _draw_edge_mech(cell: Vector3i, edge_dir: Vector3i, origin: Vector2, maxx: int, maxz: int, color: Color) -> void:
	const THICK := 2.0
	var p := _cell_px(cell, origin, maxx, maxz)
	# La carte inverse les deux axes : la voisine +x/+z est donc en -px sur la carte.
	if edge_dir.x != 0:
		var x := p.x + (0.0 if edge_dir.x > 0 else CELL_PX - THICK)
		draw_rect(Rect2(Vector2(x, p.y), Vector2(THICK, CELL_PX - 1.0)), color)
	else:
		var y := p.y + (0.0 if edge_dir.z > 0 else CELL_PX - THICK)
		draw_rect(Rect2(Vector2(p.x, y), Vector2(CELL_PX - 1.0, THICK)), color)

## Petit triangle pointant dans la direction de DÉPLACEMENT du joueur (cardinale, multiple de
## 90°) — pas le regard libre : on anticipe ainsi les déplacements effectifs.
func _draw_player_arrow(center: Vector2) -> void:
	var dir := Vector2(0.0, -1.0)  # défaut : vers le haut
	if _player.has_method("facing_delta"):
		var fd: Vector3i = _player.facing_delta()  # delta de case cardinal
		var d := Vector2(-fd.x, -fd.z)  # même inversion d'axes que la carte
		if d.length() > 0.01:
			dir = d.normalized()
	var perp := Vector2(-dir.y, dir.x)
	var r := CELL_PX * 0.6
	var pts := PackedVector2Array([
		center + dir * r,
		center - dir * r * 0.7 + perp * r * 0.6,
		center - dir * r * 0.7 - perp * r * 0.6,
	])
	draw_colored_polygon(pts, PLAYER_COLOR)
