## Piège de donjon : disarray, téléportation ou poison.
##
## Doc Notion (Level Design / Mechanisms, section Traps). Un piège se déclenche quand un
## acteur (joueur OU rival) entre sur sa case, tant qu'il est actif. Une fois déclenché, il
## ne disparaît pas : il reste VISIBLE mais désactivé (confirmé par Néd J. en commentaire).
## Il peut être révélé sans être activé (futur talent `reveal_traps`). Les effets sont
## CUMULATIFS via [AfflictionState]. Deux versions existent selon qu'il se réarme entre
## deux visites de donjon ou non ([member reactivates]).
##
## Pas de `class_name` (voir dungeon_mechanism.gd) : `extends` par chemin.
extends "res://scripts/exploration/mechanisms/dungeon_mechanism.gd"

## Type de piège. Chaque type existe en 2 versions (réarmable ou non), portées par
## [member reactivates] plutôt que par des valeurs d'enum distinctes.
enum Kind { DISARRAY, TELEPORT, POISON }

@export var kind: Kind = Kind.POISON

## Version « réarmable » : le piège redevient actif à chaque nouvelle visite du donjon.
@export var reactivates := false

## Type visible par le joueur ? Un piège révélé n'est pas pour autant désarmé (doc :
## « When revealed (but not activated), a trap also reveals its type »).
@export var revealed := false

# --- Magnitudes placeholder (à équilibrer ; la doc laisse X / Y à définir) ---

## Poison : DEN retiré par tour et nombre de tours (« loses X DEN for each of Y turns »).
##
## ## TODO(chiffrage doc) : X et Y sont toujours des lettres dans la doc. Les valeurs ci-dessous
## sont des placeholders jamais équilibrés — à confronter aux DEN de rivaux
## ([constant GameSession.RIVAL_DEN_EARLY] et suivants) et aux dégâts de chute
## ([method DungeonManager.fall_damage], eux désormais chiffrés par la doc), pour que le poison
## pèse le bon prix face aux autres sources de dégâts d'exploration.
@export var poison_per_turn := 5
@export var poison_turns := 3

## Disarray : bornes du nombre de mouvements affectés (doc : « 3-5 movements »).
@export var disarray_min := 3
@export var disarray_max := 5

## Actif = pas encore déclenché depuis la dernière (ré)initialisation.
var _active := true


func on_enter(who: Node) -> void:
	if not _active:
		return
	_trigger(who)
	_active = false  # désactivé après déclenchement, mais reste visible (grisé)
	revealed = true  # le joueur constate le piège (et son type)
	_mark_spent()  # feedback visuel : piège épuisé (usage unique par visite)
	# Un piège qui se déclenche rompt l'invisibilité (règle fog mantel).
	if who.has_method("clear_invisibility"):
		who.clear_invisibility()


## Un piège n'apparaît sur la carte qu'une fois CONNU : révélé par un talent/une capacité, ou
## constaté en le déclenchant. Tant qu'il est caché, la carte n'en dit rien (doc « User
## Interface » : la carte ne montre pas les pièges).
func shows_on_map() -> bool:
	return revealed


## Révèle le type du piège SANS le déclencher (futur talent `reveal_traps`).
func reveal() -> void:
	revealed = true


## Vrai tant que le piège n'a pas encore été déclenché depuis la dernière visite.
func is_active() -> bool:
	return _active


func is_spent() -> bool:
	return not _active


func reset_between_visits() -> void:
	if reactivates:
		_active = true
		revealed = false
		_respawn_marker()  # restaure l'aspect « armé »


func _trigger(who: Node) -> void:
	match kind:
		Kind.POISON:
			var aff = _affliction_of(who)
			if aff != null:
				aff.add_poison(poison_turns, poison_per_turn)
		Kind.DISARRAY:
			var aff = _affliction_of(who)
			if aff != null:
				aff.add_disarray(randi_range(disarray_min, disarray_max))
		Kind.TELEPORT:
			if _dungeon != null:
				_dungeon.teleport_actor(who)


## AfflictionState porté par l'acteur, ou null s'il n'en a pas (duck-typing : joueur et
## rival exposent tous deux une propriété `affliction`).
func _affliction_of(who: Node):
	return who.get("affliction")


func _spawn_visual() -> void:
	var color := Color(0.6, 0.2, 0.8)  # POISON = violet
	match kind:
		Kind.TELEPORT:
			color = Color(0.2, 0.5, 0.9)  # bleu
		Kind.DISARRAY:
			color = Color(0.9, 0.5, 0.15)  # orange
	_add_marker(color, 0.22, 0.85)  # plaque légèrement relevée
	# Piège ACTIF : luminescent, pour bien le distinguer d'un piège épuisé (grisé/mat).
	var mat := _marker.material_override as StandardMaterial3D
	if mat != null:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 0.6
