## Litière : actions Examine et Recycle.
##
## Doc Notion (Level Design / Mechanisms « Litter » + Walls + Decors). Tant qu'elle n'est
## pas recyclée, la litière est un OBSTACLE (case infranchissable) : le joueur agit depuis
## une case ADJACENTE. Deux actions :
##  - Examine : livre une info d'encyclopédie sur un spirimonstre du pool associé (1×/visite) ;
##  - Recycle : donne des objets aléatoires ET rafraîchit une capacité d'exploration au
##    hasard, puis la litière devient un sol normal (franchissable, plus d'actions).
##
## Pas de `class_name` : `extends` par chemin. Référence l'autoload GameSession.
extends "res://scripts/exploration/mechanisms/dungeon_mechanism.gd"

const ExplorationAction := preload("res://scripts/exploration/exploration_action.gd")

## Spirimonstres dont un Examine de litière peut livrer une info (doc Walls + Decors).
##
## ## TODO: la doc cite aussi « néarog », qui n'a aucune page d'espèce — donc aucun
## `data/species/néarog.tres`. Le laisser dans la liste ne produisait rien : l'espèce
## était simplement introuvable au tirage, sans erreur. À rétablir le jour où l'espèce
## existe (cf. data_integrity_check, qui vérifie désormais ces listes).
const INFO_SPECIES: Array[StringName] = [
	&"firulis", &"razel", &"kalilk", &"vilgane", &"zuk", &"hibulus",
]

## Objets qu'un recyclage peut donner (placeholder).
@export var loot_pool: Array[StringName] = [&"rune_stone", &"spade", &"tea_drop"]
@export var loot_min := 1
@export var loot_max := 2

var _recycled := false
var _examined := false

## Obstacle tant que non recyclée.
func blocks_walk() -> bool:
	return not _recycled

## Actions disponibles depuis une case adjacente (tant que non recyclée).
func on_adjacent_actions(who: Node, _facing: Vector3i) -> Array:
	if _recycled:
		return []
	var actions: Array = []
	if not _examined:
		actions.append(ExplorationAction.new(&"examine", "UI_ACTION_EXAMINE", Callable(self, "examine").bind(who)))
	actions.append(ExplorationAction.new(&"recycle", "UI_ACTION_RECYCLE", Callable(self, "recycle").bind(who)))
	return actions

func is_recycled() -> bool:
	return _recycled

## Litière recyclée : plus d'actions, la case est devenue un sol ordinaire (règle transverse).
func is_spent() -> bool:
	return _recycled

func has_been_examined() -> bool:
	return _examined

## Examine : livre une info encyclo (une fois par visite).
func examine(_who: Node) -> void:
	if _examined or _recycled:
		return
	_examined = true
	if not INFO_SPECIES.is_empty():
		var sp: StringName = INFO_SPECIES[randi() % INFO_SPECIES.size()]
		GameSession.award_ifp(sp, GameEnums.IfpAction.EXAMINE_DECOR)

## Recycle : objets aléatoires + rafraîchit une capacité d'exploration, puis sol normal.
func recycle(_who: Node) -> void:
	if _recycled:
		return
	_recycled = true
	# La case redevient un SOL NORMAL : le tas disparaît complètement (le griser laisserait
	# croire à un obstacle éteint, alors qu'on marche dessus).
	_remove_marker()
	var n := randi_range(loot_min, loot_max)
	for i in range(n):
		if not loot_pool.is_empty():
			GameSession.add_object(loot_pool[randi() % loot_pool.size()], 1)
	GameSession.refresh_random_exploration_ability()

## Persistance entre visites : une litière recyclée reste un sol normal (acquis) ; le
## replacement des décors examinés est géré au niveau donjon (incrément Examinable Decor).
func reset_between_visits() -> void:
	pass

func _spawn_visual() -> void:
	_add_marker(Color(0.35, 0.6, 0.35), 0.5, 0.75)  # tas vert (obstacle)
