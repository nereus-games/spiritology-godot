## État d'affliction porté par un acteur d'exploration (joueur ou rival).
##
## Regroupe les effets persistants infligés par les pièges (doc Notion, Level Design /
## Mechanisms, section Traps) : poison (perte de DEN par tour) et disarray (mouvements
## déviés). Les effets sont CUMULATIFS — pour un même type, seule la durée s'additionne.
##
## Pas de `class_name` : le cache des classes globales n'est régénéré que par l'éditeur,
## or le jeu se lance en CLI. On référence ce script par `preload` chez les acteurs.
extends RefCounted

## Probabilité qu'un mouvement soit dévié tant qu'on est sous disarray (doc : 35 %).
const DISARRAY_DEVIATION_CHANCE := 0.35

# Poison : durée restante (en tours) et DEN retiré à chaque tour.
var poison_turns := 0
var poison_per_turn := 0

# Disarray : file des mouvements à venir, chacun dévié (true) ou non (false). Construite à
# l'ajout selon la règle : sur N mouvements (3-5), 2 ont 35 % de chance d'être déviés et les
# N-2 autres le sont à coup sûr ; l'ordre est mélangé (façon « shuffle amélioré », pour éviter
# les séries à 0 déviation qui semblent buguées).
var _disarray_queue: Array[bool] = []

var _rng := RandomNumberGenerator.new()


## `seed_value >= 0` rend l'aléatoire (déviation disarray) déterministe pour les tests.
func _init(seed_value := -1) -> void:
	if seed_value >= 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()


## Ajoute du poison. Cumul : la durée s'additionne, la magnitude prend le plus fort (doc :
## « only the duration is augmented »).
func add_poison(turns: int, per_turn: int) -> void:
	poison_turns += maxi(turns, 0)
	poison_per_turn = maxi(poison_per_turn, maxi(per_turn, 0))


## Ajoute une salve de disarray de `moves` mouvements (cumulatif). Règle : 2 mouvements à 35 %,
## les `moves - 2` autres déviés à coup sûr, ordre mélangé.
func add_disarray(moves: int) -> void:
	var n := maxi(moves, 0)
	if n <= 0:
		return
	var forced := maxi(n - 2, 0)
	var seg: Array[bool] = []
	for i in range(forced):
		seg.append(true)
	for i in range(n - forced):  # les 2 (ou moins) restants : 35 %
		seg.append(_rng.randf() < DISARRAY_DEVIATION_CHANCE)
	# Mélange (Fisher-Yates avec le rng interne, pour un ordre aléatoire déterministe en test).
	for i in range(seg.size() - 1, 0, -1):
		var j := _rng.randi() % (i + 1)
		var tmp := seg[i]
		seg[i] = seg[j]
		seg[j] = tmp
	_disarray_queue.append_array(seg)


func has_poison() -> bool:
	return poison_turns > 0


func has_disarray() -> bool:
	return not _disarray_queue.is_empty()


## Nombre de mouvements de disarray restants (pour l'affichage HUD).
func remaining_disarray() -> int:
	return _disarray_queue.size()


func is_afflicted() -> bool:
	return has_poison() or has_disarray()


## Fait s'écouler un tour de poison. Retourne le DEN à retirer ce tour (0 si non empoisonné).
func tick_poison() -> int:
	if poison_turns <= 0:
		return 0
	poison_turns -= 1
	return poison_per_turn


## Consulte le prochain mouvement SANS le consommer : `true` s'il serait dévié. Sert au regard
## libre, où la déviation s'applique au geste alors que le décompte n'a lieu que si ce geste
## enclenche vraiment une rotation (cf. [code]PlayerInputHandler._disarrayed_mouse[/code]) — un
## piège qu'on purgerait en agitant la souris sans jamais dépenser de tour n'en serait pas un.
func peek_move() -> bool:
	return _disarray_queue[0] if not _disarray_queue.is_empty() else false


## Consomme le prochain mouvement de la file de disarray. Retourne `true` si CE mouvement doit
## être dévié. Sans disarray restant, retourne toujours `false`.
##
## Ce qui compte pour UN mouvement (doc, plus d'exception pour la caméra libre depuis le
## 2026-09-02) : un pas, une rotation au clavier, une rotation ENCLENCHÉE au regard libre, et
## chaque case franchie sur un pont étroit — où la déviation, elle, ne s'applique pas faute
## d'autre direction possible. Un geste de souris qui n'enclenche aucune rotation est dévié
## sans rien décompter ([method peek_move]).
##
## TODO (rencontre) : la doc prévoit qu'un disarray encore actif à l'ouverture d'une rencontre
## y continue — « each player action count as a movement and has 35% or 100% chance of being a
## different one than chosen ». RIEN n'est branché : la couche `scripts/encounter/` ne connaît
## pas les afflictions, ni pour le joueur ni pour les rivaux (même câblage manquant que le
## transfert du poison d'un rival vers la rencontre). À traiter quand exploration et rencontre
## seront mieux reliées ; il faudra d'abord trancher ce qu'« une autre action » désigne dans le
## menu de rencontre : une autre capacité, une autre cible, ou les deux.
func consume_move() -> bool:
	if _disarray_queue.is_empty():
		return false
	return _disarray_queue.pop_front()


## Soigne intégralement le poison (objet Tea drop / [enum GameEnums.ObjectEffect] CURE_POISON).
func cure_poison() -> void:
	poison_turns = 0
	poison_per_turn = 0
