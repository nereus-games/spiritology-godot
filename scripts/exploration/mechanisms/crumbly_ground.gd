## Sol friable : action Dig.
##
## Doc Notion (Level Design / Mechanisms « Crumbly Grounds » + Walls + Decors). Le joueur,
## DEBOUT sur la case, peut creuser (Dig) en dépensant une pelle. Le creusage livre : un
## objet aléatoire, et/ou une info d'encyclopédie sur un spirimonstre du pool associé, et/ou
## déclenche un piège. Creusable une seule fois par visite (une icône marque la case après).
## Un sol friable ne peut pas être Examiné (le Dig s'en charge).
##
## Pas de `class_name` : `extends` par chemin. Référence l'autoload GameSession (comme
## player_controller) : OK en jeu (chargé après le boot), à charger au runtime dans les tests.
extends "res://scripts/exploration/mechanisms/dungeon_mechanism.gd"

const ExplorationAction := preload("res://scripts/exploration/exploration_action.gd")

const SPADE := &"spade"

## Spirimonstres dont un Dig peut livrer une info encyclo (doc Walls + Decors).
const INFO_SPECIES: Array[StringName] = [
	&"mastel", &"kurkab", &"sopiark", &"firulis", &"skorpis", &"yilir",
]

## Objets qu'un creusage peut donner (placeholder ; loot précis à définir côté design).
@export var loot_pool: Array[StringName] = [&"rune_stone", &"tea_drop", &"smoke_bomb"]
## Probabilité de livrer une info d'encyclopédie en plus de l'objet.
@export var info_chance := 0.5
## Probabilité de déclencher un piège (empoisonne le creuseur) — placeholder.
@export var trap_chance := 0.25
@export var trap_poison_turns := 3
@export var trap_poison_per_turn := 5

var _dug := false

## Action Dig, seulement si le joueur est sur la case, qu'elle n'a pas déjà été creusée, et
## qu'il possède une pelle.
func on_tile_actions(who: Node) -> Array:
	if _dug or not GameSession.has_object(SPADE):
		return []
	return [ExplorationAction.new(&"dig", "UI_ACTION_DIG", Callable(self, "dig").bind(who))]

## Vrai si la case a déjà été creusée cette visite (icône sur la carte).
func has_been_dug() -> bool:
	return _dug

## Déjà creusé cette visite : plus d'action Dig (règle transverse « épuisé »). C'est aussi ce
## que lit la carte pour marquer la case, comme le demande la doc (« an icon is shown on the
## dungeon map after it has been dug a first time »).
func is_spent() -> bool:
	return _dug

## Creuse : dépense une pelle, puis livre objet / info / piège. Sans pelle, ne fait rien.
func dig(who: Node) -> void:
	if _dug or not GameSession.consume_object(SPADE):
		return
	_dug = true
	# Sol retourné : grisé mais PAS aplati (la plaque est déjà quasi au ras du sol ;
	# l'écraser encore la ferait disparaître).
	_grey_marker()
	# 1) Objet aléatoire.
	if not loot_pool.is_empty():
		GameSession.add_object(loot_pool[randi() % loot_pool.size()], 1)
	# 2) Info encyclo (optionnelle).
	if randf() < info_chance and not INFO_SPECIES.is_empty():
		var sp: StringName = INFO_SPECIES[randi() % INFO_SPECIES.size()]
		GameSession.award_ifp(sp, GameEnums.IfpAction.EXAMINE_DECOR)
	# 3) Piège (optionnel) : empoisonne le creuseur.
	if randf() < trap_chance:
		var aff = who.get("affliction")
		if aff != null:
			aff.add_poison(trap_poison_turns, trap_poison_per_turn)

func reset_between_visits() -> void:
	_dug = false
	_respawn_marker()  # creusable de nouveau : la terre retrouve sa couleur

func _spawn_visual() -> void:
	_add_marker(Color(0.5, 0.35, 0.2), 0.1, 0.9)  # sol terreux, très plat
