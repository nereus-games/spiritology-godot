## Case de pont étroit (tronc au-dessus du vide) — test d'équilibre.
##
## Doc Notion : le personnage AVANCE SEUL ; le joueur corrige en temps réel par des mouvements
## latéraux pour rester en équilibre. Chaque case du pont porte ce mécanisme : entrer dessus
## engage un test d'équilibre qui fait avancer d'UNE case dans le sens du REGARD (donc le pont
## fonctionne dans les deux sens). La logique d'équilibre pure vit dans [NarrowBridgeBalance] ;
## le pilote temps réel (entrée latérale, roulis caméra, chaînage de case en case, chute) est
## dans `exploration.gd`.
##
## Pas de `class_name` : `extends` par chemin. Référence l'autoload GameSession (score PSY).
extends "res://scripts/exploration/mechanisms/dungeon_mechanism.gd"

const NarrowBridgeBalance := preload("res://scripts/exploration/narrow_bridge_balance.gd")

var _balance
var _engaged := false
var _dir := Vector3i(0, 0, 1)


## Un pont n'est pas un obstacle : on peut y entrer (ce qui engage le test).
func blocks_walk() -> bool:
	return false


func on_enter(who: Node) -> void:
	if _engaged:
		return
	if _dungeon != null and not _dungeon.is_player(who):
		return  # le test d'équilibre ne concerne que le joueur
	var disarrayed := false
	var aff = who.get("affliction")
	if aff != null:
		disarrayed = aff.has_disarray()
	engage(who.facing_delta(), disarrayed)


## Engage le test d'équilibre pour avancer d'UNE case dans la direction `dir`.
func engage(dir: Vector3i, disarrayed: bool) -> void:
	_dir = dir if dir != Vector3i.ZERO else Vector3i(0, 0, 1)
	_balance = NarrowBridgeBalance.new()
	_balance.configure(GameSession.psy_score, 1, disarrayed)  # 1 case
	_engaged = true


## Reprend le test d'équilibre DÉJÀ EN COURS (traversée entamée sur la case précédente) au
## lieu d'en démarrer un neuf : le déséquilibre et la vitesse latérale traversent le bord de
## case, sinon l'élan serait effacé toutes les 2 s (l'inverse d'une inertie).
func adopt_balance(running) -> void:
	if running == null:
		return
	_balance = running
	_balance.restart_cell()


## Fait avancer le test d'un pas de temps avec l'entrée latérale (∈ [-1, 1]). Retourne
## &"balancing", &"fell" ou &"complete".
func advance(delta: float, lateral_input: float) -> StringName:
	if not _engaged or _balance == null:
		return &"complete"
	_balance.tick(delta, lateral_input)
	if _balance.is_fallen():
		_engaged = false
		return &"fell"
	if _balance.is_complete():
		_engaged = false
		return &"complete"
	return &"balancing"


func is_engaged() -> bool:
	return _engaged


func direction() -> Vector3i:
	return _dir


## Accès au modèle d'équilibre (le pilote lit/écrit imbalance pour le chaînage).
func balance():
	return _balance

# Pas de marqueur générique : le visuel (planches) est posé par le scénario / level design.
