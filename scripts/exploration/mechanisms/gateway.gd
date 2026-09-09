## Porte de donjon : automatisée, verrouillée ou de méditation.
##
## Doc Notion (Level Design / Mechanisms, section Gateways) : ce sont des portes COULISSANTES.
## Une porte n'occupe donc AUCUNE case : elle est posée sur l'ARÊTE entre deux cases voisines
## (la case d'ancrage [member cell] et sa voisine dans [member edge_dir]) et barre ce passage
## tant qu'elle est fermée ([method blocks_walk]). Fine ([constant DungeonManager.EDGE_THICKNESS]),
## elle laisse la place de se tenir de chaque côté ; on peut donc lui faire face depuis les deux
## bords, et ses actions (ouvrir, méditer) sont disponibles des deux côtés.
##
## Trois types :
##  - AUTOMATED : ouvre/ferme selon un motif fixe cyclé chaque tour (défaut sur 3 tours :
##    fermé, fermé, ouvert). Le motif peut différer d'une porte à l'autre ([member phase_offset]).
##  - LOCKED : s'ouvre contre des objets (puis reste ouverte). Alternative à une route
##    dangereuse au prix de ressources. Le « OU » de la doc (tôt = 2 pelles ou 4 pierres
##    runiques ; tard = 4 pelles ou 6 pierres runiques) est un choix de LEVEL DESIGN, pas une
##    alternative offerte au joueur : chaque porte exige UNE monnaie ([member cost_currency]),
##    dont le montant se déduit du palier ([member cost_tier]).
##  - MEDITATION : s'ouvre après N méditations CONSÉCUTIVES devant elle (puis reste ouverte).
##    « Consécutives » (doc) = sans rien faire d'autre entre-temps : la série tombe dès qu'un
##    tour s'écoule alors que le joueur a quitté la case d'où il méditait, ou s'en est détourné.
##
## Pas de `class_name` (voir dungeon_mechanism.gd) : `extends` par chemin. Les actions joueur
## (ouvrir une porte verrouillée, méditer) sont exposées comme méthodes publiques et remontent
## au menu contextuel du HUD via [method DungeonManager.actions_for].
extends "res://scripts/exploration/mechanisms/dungeon_mechanism.gd"

const ExplorationAction := preload("res://scripts/exploration/exploration_action.gd")

enum Kind { AUTOMATED, LOCKED, MEDITATION }

## Palier de donjon, conditionne le coût d'une porte verrouillée.
enum CostTier { EARLY, LATE }

## Barème des coûts d'ouverture par palier et par monnaie. Le level design choisit la monnaie
## de chaque porte ; ce tableau n'en donne que le tarif. Slugs d'objets tels que générés dans
## `data/objects/`.
const LOCKED_COSTS := {
	CostTier.EARLY: {&"spade": 2, &"rune_stone": 4},
	CostTier.LATE: {&"spade": 4, &"rune_stone": 6},
}

@export var kind: Kind = Kind.AUTOMATED

## Voisine barrée : la porte est sur l'arête entre [member cell] et `cell + edge_dir`.
## Toujours une direction horizontale unitaire (±X ou ±Z).
@export var edge_dir := Vector3i(0, 0, 1)

## AUTOMATED : motif d'ouverture cyclé (un booléen par tour). Défaut doc = fermé/fermé/ouvert.
@export var open_pattern: Array[bool] = [false, false, true]
## AUTOMATED : décalage de phase, pour que deux portes ne soient pas synchrones.
@export var phase_offset := 0

## LOCKED : palier de coût, qui fixe le MONTANT exigé.
@export var cost_tier: CostTier = CostTier.EARLY

## LOCKED : monnaie exigée par CETTE porte, arrêtée au level design. Avec [member cost_tier],
## elle détermine entièrement le prix (cf. [method locked_cost]).
@export var cost_currency: StringName = &"spade"

## MEDITATION : nombre de méditations requises pour ouvrir.
@export var meditations_required := 3

var _open := false
var _meditations := 0

# Série de méditations en cours : case d'où le joueur médite et direction qu'il regarde. Sert
# à vérifier, à chaque tour, qu'il est TOUJOURS là (sinon la série est rompue).
var _streak_tile := Vector3i.ZERO
var _streak_facing := Vector3i.ZERO
var _streak_open := false

## Sur l'arête, pas sur la case : la case d'ancrage reste praticable.
func _register() -> void:
	_dungeon.register_edge_mechanism(cell, cell + edge_dir, self)

func _unregister() -> void:
	_dungeon.unregister_edge_mechanism(cell, cell + edge_dir, self)

func _on_registered() -> void:
	# État initial d'une porte automatisée = première valeur du motif (au décalage près).
	if kind == Kind.AUTOMATED and not open_pattern.is_empty():
		_open = open_pattern[phase_offset % open_pattern.size()]

## Une porte fermée barre l'arête qu'elle occupe (consulté par [method DungeonManager.is_edge_blocked]).
func blocks_walk() -> bool:
	return not _open

## Vrai si la porte est ouverte.
func is_open() -> bool:
	return _open

## Actions quand on FAIT FACE à la porte, de l'un ou l'autre côté : ouvrir une porte
## verrouillée (paiement) ou méditer devant une porte de méditation, tant qu'elles sont
## fermées. (Les portes automatisées n'ont pas d'action : elles cyclent seules.)
func on_adjacent_actions(who: Node, facing: Vector3i) -> Array:
	if _open:
		return []
	if kind == Kind.LOCKED:
		return [ExplorationAction.new(&"open_gate", "UI_ACTION_OPEN_GATE", Callable(self, "try_open_locked"))]
	if kind == Kind.MEDITATION:
		# La case et la direction sont figées dans l'action : c'est de LÀ que la méditation
		# comptera, et c'est ce poste qu'il faudra tenir pour enchaîner la série.
		var from_tile: Vector3i = who.cell if who != null and "cell" in who else cell
		return [ExplorationAction.new(&"meditate", "UI_ACTION_MEDITATE",
			Callable(self, "meditate").bind(from_tile, facing))]
	return []

func on_turn(turn: int) -> void:
	# Seules les portes automatisées cyclent ; LOCKED/MEDITATION restent ouvertes une fois
	# ouvertes.
	if kind == Kind.AUTOMATED and not open_pattern.is_empty():
		# Une porte est entre les cases : elle ne peut pas se refermer SUR le joueur (il est
		# toujours d'un côté ou de l'autre), le motif s'applique donc tel quel.
		_open = open_pattern[(turn + phase_offset) % open_pattern.size()]
		_update_marker()
	elif kind == Kind.MEDITATION and _streak_open and not _open:
		# Un tour vient de s'écouler : la série ne tient que si le joueur n'a pas bougé de son
		# poste (déplacement, chute, téléportation) ni tourné le regard ailleurs.
		if not _player_holds_post():
			_break_streak()

## Le joueur est-il toujours sur la case d'où il a médité, tourné vers cette porte ?
func _player_holds_post() -> bool:
	if _dungeon == null or _dungeon.player_cell() != _streak_tile:
		return false
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not player.has_method("facing_delta"):
		return true  # orientation inconnue : on ne casse pas la série sur un doute
	return player.facing_delta() == _streak_facing

## Rompt la série en cours : le compteur repart de zéro (et l'affichage avec).
func _break_streak() -> void:
	_streak_open = false
	if _meditations == 0:
		return
	_meditations = 0
	_update_gate_label()

## Prix de cette porte : montant de [member cost_currency] exigé au palier [member cost_tier].
## 0 si ce n'est pas une porte verrouillée, ou si la monnaie posée n'a pas de tarif au barème
## (level design en faute : la porte serait alors infranchissable).
func locked_cost() -> int:
	if kind != Kind.LOCKED:
		return 0
	return LOCKED_COSTS[cost_tier].get(cost_currency, 0)

## Tente d'ouvrir une porte verrouillée en payant son prix. Une porte exige UNE monnaie,
## choisie au level design : il n'y a rien à arbitrer côté joueur. Consomme les objets et
## ouvre si le joueur peut payer. Retourne `true` si la porte est ouverte à l'issue.
func try_open_locked() -> bool:
	if kind != Kind.LOCKED:
		return _open
	if _open:
		return true
	var need := locked_cost()
	if need <= 0 or GameSession.object_count(cost_currency) < need:
		return false
	GameSession.remove_object(cost_currency, need)
	_open = true
	_update_marker()
	_update_gate_label()
	return true

## Comptabilise une méditation devant une porte de méditation, faite depuis `from_tile` en
## regardant `facing`. Ouvre la porte au N-ième palier ([member meditations_required]) — à
## condition que les méditations soient CONSÉCUTIVES : changer de poste entre deux remet le
## compteur à zéro (voir [method on_turn]). Retourne `true` si la porte est ouverte à l'issue.
func meditate(from_tile := Vector3i.ZERO, facing := Vector3i.ZERO) -> bool:
	if kind != Kind.MEDITATION:
		return _open
	if _open:
		return true
	# Méditer depuis un autre poste que la série en cours la remplace (elle ne la prolonge pas).
	if _streak_open and (from_tile != _streak_tile or facing != _streak_facing):
		_meditations = 0
	_streak_tile = from_tile
	_streak_facing = facing
	_streak_open = true
	_meditations += 1
	if _meditations >= meditations_required:
		_open = true
	_update_gate_label()
	_update_marker()
	return _open

## Réarmement à l'entrée d'un donjon : les portes automatisées reprennent leur motif ; les
## portes verrouillées/méditation restent ouvertes (l'ouverture est acquise pour la partie).
func reset_between_visits() -> void:
	if kind == Kind.AUTOMATED:
		if not open_pattern.is_empty():
			_open = open_pattern[phase_offset % open_pattern.size()]
	elif kind == Kind.MEDITATION and not _open:
		_break_streak()  # sortir du donjon rompt la série (elle doit être consécutive)

## Hauteur du battant (mètres) : plus haut que les yeux du duo, sans dépasser la case.
const GATE_HEIGHT := 0.9
## Largeur du battant : presque toute la largeur de l'arête, en laissant un jour aux montants.
const GATE_WIDTH := 0.9

## Inscription portée par CHAQUE face du battant (une porte se lit des deux côtés) : coût
## d'ouverture pour une porte verrouillée, compteur de méditations pour une porte de méditation.
var _face_labels: Array[Label3D] = []

func _spawn_visual() -> void:
	var color := Color(0.55, 0.55, 0.6)  # AUTOMATED = gris
	match kind:
		Kind.LOCKED:
			color = Color(0.7, 0.6, 0.2)      # doré (paiement)
		Kind.MEDITATION:
			color = Color(0.4, 0.7, 0.6)      # vert-bleu (méditation)
	# Battant fin, posé SUR l'arête : épais dans l'axe franchi, large dans l'autre. L'origine
	# du nœud est au centre de la case d'ancrage → on le décale d'une demi-case vers l'arête.
	var thin := DungeonManager.EDGE_THICKNESS
	var across := Vector3(GATE_WIDTH, GATE_HEIGHT, GATE_WIDTH)
	if edge_dir.x != 0:
		across.x = thin
	else:
		across.z = thin
	var offset := Vector3(edge_dir.x, 0.0, edge_dir.z) * DungeonManager.CELL_SIZE * 0.5
	_add_marker_box(color, across, offset)
	if kind == Kind.LOCKED or kind == Kind.MEDITATION:
		_spawn_face_labels(offset, color)
	_update_marker()

## Inscrit le coût / le compteur SUR le battant, une fois par face (plaqué contre la face,
## orientée vers l'extérieur), et non flottant au-dessus : une porte fait la hauteur du duo,
## un texte posé plus haut passerait hors du champ de vision. Les deux faces portent la même
## inscription : une porte s'ouvre des deux côtés, elle doit donc se lire des deux côtés (doc).
func _spawn_face_labels(offset: Vector3, color: Color) -> void:
	var normal := Vector3(edge_dir.x, 0.0, edge_dir.z).normalized()
	for face in [normal, -normal]:
		var label := Label3D.new()
		label.font_size = 64
		label.pixel_size = 0.0022               # ≈ 14 cm de haut sur un battant de 90 cm
		label.modulate = color.lightened(0.45)
		# Un prix nomme son objet (« 2 × pierre runique ») : sans repli à la ligne, l'inscription
		# déborderait du battant. On la borne à sa largeur.
		label.width = GATE_WIDTH / label.pixel_size
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		label.no_depth_test = false
		# Plaqué juste devant la face du battant, à hauteur des yeux du duo : droit dans l'axe
		# du regard, sans avoir à baisser la tête (le battant monte assez haut pour l'accueillir).
		label.position = offset + face * (DungeonManager.EDGE_THICKNESS * 0.5 + 0.004) \
			+ Vector3(0.0, DungeonManager.EYE_HEIGHT, 0.0)
		label.rotation.y = atan2(face.x, face.z)  # +Z du Label3D = sens de lecture
		add_child(label)
		_face_labels.append(label)
	_update_gate_label()

## Reflète l'état ouvert/fermé : fermée = battant relevé ; ouverte = coulissée au ras du sol.
func _update_marker() -> void:
	_flatten_marker(_open)

## Ce qu'une porte fermée annonce d'elle-même : son prix (doc « easily identified because shown
## on the gate itself ») ou l'avancement de la série de méditations. Une fois ouverte, elle n'a
## plus rien à dire.
func _update_gate_label() -> void:
	var text := ""
	if not _open:
		match kind:
			Kind.LOCKED:
				var obj := GameData.object(cost_currency)
				var currency := tr(obj.name_key()) if obj != null else String(cost_currency)
				text = "%d × %s" % [locked_cost(), currency]
			Kind.MEDITATION:
				text = "%d/%d" % [_meditations, meditations_required]
	for label in _face_labels:
		label.text = text
