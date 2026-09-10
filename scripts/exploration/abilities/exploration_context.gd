## What an exploration effect — an exploration ability or an object — is given to work with.
##
## The exploration counterpart of [EncounterContext]: it holds the references to the
## exploration world (dungeon, player) and exposes the PRIMITIVES an effect can trigger —
## invisibility, not-chased, healing, crossing a cracked wall. Effects never touch the player or
## the session directly; they go through these methods, which record what they did in
## [member log].
##
## No `class_name` (the CLI class-cache trap): referenced by `preload`. References the
## GameSession autoload — fine in game, but tests have to load it at runtime.
extends RefCounted

var dungeon  ## DungeonManager
var player  ## PlayerController (a Node)
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
# Effect primitives
# --------------------------------------------------------------------------


## Hides the player from the rivals for `tiles` moves (fog mantel). Cleared by an encounter OR
## by springing a trap.
func hide_from_rivals(tiles: int) -> void:
	if player != null and player.has_method("set_invisible"):
		player.set_invisible(tiles)
	_note("invisible pour %d cases" % tiles)


## Stops the rivals chasing the player for `moves` moves (torment veil, a costume).
## `disguise_species` is the species being impersonated, when there is one.
func avoid_pursuit(moves: int, disguise_species: StringName = &"") -> void:
	if player != null and player.has_method("set_unpursued"):
		player.set_unpursued(moves, disguise_species)
	_note("non-poursuivi pour %d cases" % moves)


## Cures the player's poison outright (a tea drop, or an anti-poison ability).
func cure_poison() -> void:
	if player != null:
		var aff = player.get("affliction")
		if aff != null:
			aff.cure_poison()
	_note("poison soigné")


## Gives `amount` DEN back to both characters of the duo (a rune stone).
func heal_duo(amount: int) -> void:
	GameSession.heal_den(GameSession.PartySlot.MAIN, amount)
	GameSession.heal_den(GameSession.PartySlot.TEAMMATE, amount)
	_note("duo soigné de %d DEN" % amount)


## Crosses the cracked wall on the cell being faced, if there is one (cranny crossing). Returns
## true when the crossing happened.
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


## Scouting (static camouflage): the player holds still to watch the wandering rival groups.
## ## TODO: reveal 2 to 4 groups one at a time and offer to take them on. This needs a
## rival-group spawn system, which does not exist. Placeholder: goes hidden for the watch.
func scout_groups() -> void:
	hide_from_rivals(3)
	_note("guet — révélation de groupes de rivaux TODO")
