## Coffre.
##
## Doc Notion (Level Design / Mechanisms « Chest »). Mécanisme rare : en marchant dessus,
## le joueur reçoit des objets. Certains coffres sont en réalité des pièges de téléportation
## déguisés ([member is_trap]) — rien ne les distingue à l'œil. Ouvert une seule fois, y
## compris entre deux visites.
##
## Deux autres pages de la doc mentionnent les coffres, et les deux sont câblées ici :
##  - talent « Reveal Traps » (razél) : « When a chest attempts to teleport players, they can
##    decide to teleport or not. The chest gives 1 or more object no matter what, but more if
##    players choose to teleport. » → un coffre piégé propose alors un CHOIX (menu d'actions
##    de la case, comme le dieverting), et livre du butin dans les deux cas ;
##  - talent « Trick to Reveal » (érzélak) : révèle sur la carte « a chest or trap that hadn't
##    been revealed yet » → d'où [member revealed] / [method reveal], symétriques de [Trap].
##
## Pas de `class_name` : `extends` par chemin. Référence l'autoload GameSession.
extends "res://scripts/exploration/mechanisms/dungeon_mechanism.gd"

const ExplorationAction := preload("res://scripts/exploration/exploration_action.gd")

## Talent qui rend optionnelle la téléportation d'un coffre piégé (doc « Reveal Traps »).
const REVEAL_TRAPS := &"reveal_traps"

## Coffre piégé : au lieu de donner des objets, téléporte celui qui l'ouvre.
@export var is_trap := false

## Objets qu'un coffre peut contenir (placeholder).
@export var loot_pool: Array[StringName] = [&"rune_stone", &"tea_drop", &"smoke_bomb", &"spade"]
@export var loot_min := 1
@export var loot_max := 3

## Butin d'un coffre PIÉGÉ ouvert par un duo qui porte « Reveal Traps » : la doc impose
## « 1 or more object no matter what, but more if players choose to teleport ». Magnitudes
## placeholder, avec la seule contrainte de la doc (accepté > refusé ≥ 1).
@export var trap_loot_declined := 1
@export var trap_loot_accepted := 3

## Contenu IMPOSÉ : si non vide, le coffre livre EXACTEMENT ces objets (doublons compris) au
## lieu de tirer dans [member loot_pool]. Sert au dieverting, qui dépose les objets qu'il fait
## perdre dans un coffre posé là où il se trouvait (doc « Dieverting »).
@export var fixed_loot: Array[StringName] = []

## Coffre repéré par le joueur (marché dessus, ou révélé par « Trick to Reveal »). N'implique
## PAS de savoir s'il est piégé : la doc en fait des pièges DÉGUISÉS.
## ## TODO: la carte ne dessine pas encore les mécanismes ; ce drapeau est ce qu'elle lira
## (même chantier que `Trap.revealed`).
@export var revealed := false

var _opened := false
## Coffre piégé rencontré par un duo qui porte « Reveal Traps » : choix en attente sur la
## case (téléportation acceptée ou refusée), comme le choix détruire/subir du dieverting.
var _pending := false

func is_opened() -> bool:
	return _opened

## Un coffre ouvert n'a plus rien à donner (règle transverse « épuisé »).
func is_spent() -> bool:
	return _opened

## Un choix téléportation oui/non est-il en attente sur cette case ?
func is_pending() -> bool:
	return _pending

## Révèle le coffre sur la carte sans l'ouvrir (talent « Trick to Reveal »).
func reveal() -> void:
	revealed = true

func on_enter(who: Node) -> void:
	if _opened:
		return
	var is_player := _dungeon == null or _dungeon.is_player(who)
	if is_player:
		revealed = true  # on a mis le pied dessus : le coffre n'est plus une inconnue
	if is_trap:
		# Piège déguisé : comme tout piège, il vaut aussi pour les rivaux (doc Traps, commentaire
		# Néd J. « rivals too ») — mais le choix, lui, n'est offert qu'au joueur.
		if is_player and GameSession.party_has_talent(REVEAL_TRAPS):
			_pending = true
			return
		_spring(who)
		return
	# Coffre à butin : seul le joueur ramasse (les rivaux n'ont pas d'inventaire). Un rival
	# qui passe dessus ne le consomme donc PAS — le butin attend le joueur.
	if not is_player:
		return
	_close()
	_deliver(_roll_loot())

## Actions proposées tant que le choix « Reveal Traps » est en attente (doc : téléporter ou
## non, du butin dans les deux cas — davantage si l'on accepte).
func on_tile_actions(who: Node) -> Array:
	if _opened or not _pending:
		return []
	return [
		ExplorationAction.new(&"chest_teleport", "UI_ACTION_CHEST_TELEPORT",
				Callable(self, "accept_teleport").bind(who)),
		ExplorationAction.new(&"chest_decline", "UI_ACTION_CHEST_DECLINE",
				Callable(self, "decline_teleport").bind(who)),
	]

## Choix « Reveal Traps » : accepter la téléportation, contre un butin plus généreux.
func accept_teleport(who: Node) -> void:
	if _opened or not _pending:
		return
	_close()
	_deliver(_pick_from_pool(trap_loot_accepted))
	_teleport(who)

## Choix « Reveal Traps » : refuser la téléportation ; le coffre livre quand même du butin.
## Le piège ne se déclenche pas, donc il ne rompt pas l'invisibilité (règle fog mantel).
func decline_teleport(_who: Node) -> void:
	if _opened or not _pending:
		return
	_close()
	_deliver(_pick_from_pool(trap_loot_declined))

## Le piège se déclenche : téléportation sèche, sans butin (cas ordinaire, sans talent).
func _spring(who: Node) -> void:
	_close()
	_teleport(who)

func _teleport(who: Node) -> void:
	if _dungeon != null:
		_dungeon.teleport_actor(who)
	# Un piège qui se déclenche rompt l'invisibilité (règle fog mantel), coffre ou pas.
	if is_instance_valid(who) and who.has_method("clear_invisibility"):
		who.clear_invisibility()

## Marque le coffre comme ouvert : plus d'actions, et un visuel inerte (comme un piège
## épuisé) pour qu'on ne revienne pas dessus en espérant du butin.
func _close() -> void:
	_opened = true
	_pending = false
	_mark_spent()

## Contenu du coffre : le contenu imposé s'il y en a un (dieverting), sinon un tirage.
func _roll_loot() -> Array[StringName]:
	if not fixed_loot.is_empty():
		return fixed_loot.duplicate()
	return _pick_from_pool(randi_range(loot_min, loot_max))

## `count` objets tirés au hasard dans [member loot_pool] (doublons possibles).
func _pick_from_pool(count: int) -> Array[StringName]:
	var picked: Array[StringName] = []
	if loot_pool.is_empty():
		return picked
	for i in range(count):
		picked.append(loot_pool[randi() % loot_pool.size()])
	return picked

## Verse le butin à l'inventaire et l'annonce au joueur (bandeau de messages du HUD).
func _deliver(loot: Array[StringName]) -> void:
	if loot.is_empty():
		return
	var names: Array[String] = []
	for object_id in loot:
		GameSession.add_object(object_id, 1)
		var data: ObjectData = GameData.object(object_id)
		names.append(tr(data.name_key()) if data != null else String(object_id))
	if _dungeon != null:
		_dungeon.post_message(tr("UI_CHEST_LOOT") % ", ".join(names))

## Les coffres ouverts le restent entre visites (pas de réarmement). Un choix laissé en
## suspens, lui, ne survit pas à la sortie du donjon : le coffre est de nouveau intact.
func reset_between_visits() -> void:
	_pending = false

func _spawn_visual() -> void:
	_add_marker(Color(0.75, 0.6, 0.25), 0.35, 0.55)  # coffre doré (piégé ou non : identique)
