## Contexte d'exécution d'un effet d'exploration (capacité d'exploration OU objet).
##
## Équivalent exploration de [EncounterContext] : porte les références du monde d'exploration
## (donjon, joueur) et expose les PRIMITIVES qu'un effet peut déclencher (invisibilité,
## non-poursuite, soin, traversée de mur fissuré…). Les effets ne touchent jamais directement
## le joueur / la session : ils passent par ces méthodes, journalisées dans [member log].
##
## Pas de `class_name` (piège du cache CLI) : référencé par `preload`. Référence l'autoload
## GameSession (OK en jeu ; charger au runtime dans les tests).
extends RefCounted

var dungeon      ## DungeonManager
var player       ## PlayerController (Node)
var rng: RandomNumberGenerator
var log: Array[String] = []

func _init(p_dungeon = null, p_player = null, p_rng: RandomNumberGenerator = null) -> void:
	dungeon = p_dungeon
	player = p_player
	if p_rng != null:
		rng = p_rng
	else:
		rng = RandomNumberGenerator.new()
		rng.randomize()

func _note(msg: String) -> void:
	log.append(msg)

# --------------------------------------------------------------------------
# Primitives d'effet
# --------------------------------------------------------------------------

## Rend le joueur invisible des rivaux pendant `tiles` déplacements (fog mantel). Annulé par
## une rencontre OU l'activation d'un piège.
func hide_from_rivals(tiles: int) -> void:
	if player != null and player.has_method("set_invisible"):
		player.set_invisible(tiles)
	_note("invisible pour %d cases" % tiles)

## Empêche les rivaux de poursuivre le joueur pendant `moves` déplacements (torment veil /
## costume). `disguise_species` = espèce dont on prend l'apparence, le cas échéant.
func avoid_pursuit(moves: int, disguise_species: StringName = &"") -> void:
	if player != null and player.has_method("set_unpursued"):
		player.set_unpursued(moves, disguise_species)
	_note("non-poursuivi pour %d cases" % moves)

## Soigne intégralement le poison du joueur (tea drop / capacité anti-poison).
func cure_poison() -> void:
	if player != null:
		var aff = player.get("affliction")
		if aff != null:
			aff.cure_poison()
	_note("poison soigné")

## Rend `amount` DEN aux deux personnages du duo (rune stone).
func heal_duo(amount: int) -> void:
	GameSession.heal_den(GameSession.PartySlot.MAIN, amount)
	GameSession.heal_den(GameSession.PartySlot.TEAMMATE, amount)
	_note("duo soigné de %d DEN" % amount)

## Traverse le mur fissuré de la case regardée, s'il y en a un (cranny crossing). Retourne
## true si la traversée a eu lieu.
func cross_faced_cracked_wall() -> bool:
	if dungeon == null or player == null:
		return false
	var facing: Vector3i = player.facing_delta()
	var target: Vector3i = player.cell + facing
	for m in dungeon.mechanisms_at(target):
		if m.has_method("cross"):
			m.cross(player, facing)
			_note("mur fissuré traversé")
			return true
	_note("aucun mur fissuré en face")
	return false

## Guet (static camouflage) : le joueur se fige pour observer les groupes de rivaux errants.
## ## TODO: révéler 2 à 4 groupes un par un et proposer de les affronter — dépend d'un système
## de spawn de groupes de rivaux, absent. Placeholder : passe en état caché le temps du guet.
func scout_groups() -> void:
	hide_from_rivals(3)
	_note("guet — révélation de groupes de rivaux TODO")
