## Décor examinable.
##
## Doc Notion (Level Design / Walls + Decors). 10-15 % des infos d'encyclopédie ne s'obtiennent
## pas en rencontre mais en Examinant des éléments de décor dédiés, qui livrent une info au
## hasard sur un spirimonstre d'un pool propre au TYPE de décor. Examinable une seule fois par
## visite. (Litter et Crumbly Grounds ont leurs propres mécanismes ; ici : Gooey Marks,
## Posters, Scratch Marks.) Si le score PSY est élevé, l'interaction a une chance de faire
## apparaître des rivaux à proximité.
##
## Pas de `class_name` : `extends` par chemin. Référence l'autoload GameSession.
extends "res://scripts/exploration/mechanisms/dungeon_mechanism.gd"

const ExplorationAction := preload("res://scripts/exploration/exploration_action.gd")

enum DecorType { GOOEY_MARKS, POSTERS, SCRATCH_MARKS }

## Pools de spirimonstres par type de décor (doc Walls + Decors).
const POOLS := {
	DecorType.GOOEY_MARKS: [
		&"kurkab", &"malcouli", &"sénskor", &"spodra", &"sadakbia",
		&"fonéchal", &"kalilk", &"mazir", &"sopiark",
	],
	DecorType.POSTERS: [
		&"jézal", &"zuk", &"fopin", &"oléni", &"érzélak", &"ravbak", &"gélmi", &"niyat",
	],
	DecorType.SCRATCH_MARKS: [
		&"yadol", &"gaiaz", &"draka", &"kalilk", &"razél", &"érdouss", &"vérnal",
	],
}

@export var decor_type: DecorType = DecorType.POSTERS

var _examined := false

func has_been_examined() -> bool:
	return _examined

## Décor déjà examiné : plus d'info à en tirer cette visite (règle transverse « épuisé »).
func is_spent() -> bool:
	return _examined

## Examine disponible depuis une case adjacente, une fois par visite.
func on_adjacent_actions(who: Node, _facing: Vector3i) -> Array:
	if _examined:
		return []
	return [ExplorationAction.new(&"examine", "UI_ACTION_EXAMINE", Callable(self, "examine").bind(who))]

## Examine : livre une info encyclo sur un spirimonstre du pool du type de décor.
func examine(_who: Node) -> void:
	if _examined:
		return
	_examined = true
	# Décor lu : grisé sans aplatissement (c'est un élément mural, l'écraser au sol n'aurait
	# aucun sens).
	_grey_marker()
	var pool: Array = POOLS[decor_type]
	if not pool.is_empty():
		GameSession.award_ifp(pool[randi() % pool.size()], GameEnums.IfpAction.EXAMINE_DECOR)
	# ## TODO: si PSY élevé, chance de faire apparaître 1+ rivaux à proximité (pas sur la case
	## du joueur). Seuil « how much? » non chiffré dans Notion ; nécessite un système de spawn.

## Persistance entre visites : un décor non examiné garde sa place ; un décor examiné disparaît
## et est remplacé ailleurs (géré au niveau donjon). Ici on conserve simplement l'état.
func reset_between_visits() -> void:
	pass

func _spawn_visual() -> void:
	_add_marker(Color(0.7, 0.3, 0.7), 0.65, 0.3)  # décor magenta, fin (affiche/marque)
