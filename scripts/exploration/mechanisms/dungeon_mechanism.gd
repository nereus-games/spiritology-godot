## Brique de base d'un mécanisme de donjon posé sur la grille.
##
## Un mécanisme s'attache à UNE case et s'enregistre auprès du [DungeonManager] (comme un
## [RivalBehavior]), au lieu d'être sondé par des raycasts dispersés. Les sous-classes
## (Trap, et plus tard Gateway, SpecialGround, Chest…) surchargent les hooks pertinents.
##
## Pas de `class_name` : le cache des classes globales n'est régénéré que par l'éditeur,
## or le jeu se lance en CLI ; on référence donc ce script par `preload` / `extends` chemin
## (voir la mémoire de projet sur le sujet). Le [DungeonManager] manipule les mécanismes en
## duck-typing (appels de méthodes), sans dépendre d'un type global.
extends Node3D

## Case occupée par ce mécanisme (dérivée de la position monde au boot).
var cell: Vector3i

var _dungeon: DungeonManager

func _ready() -> void:
	add_to_group("dungeon_mechanism")
	_dungeon = get_tree().get_first_node_in_group("dungeon") as DungeonManager
	if _dungeon == null:
		push_error("[DungeonMechanism] aucun DungeonManager dans le groupe 'dungeon'.")
		return
	cell = _dungeon.world_to_cell(global_position)
	_register()
	_on_registered()
	_spawn_visual()

## Enregistrement auprès du donjon. Défaut : sur la case. Surchargé par les mécanismes posés
## sur une ARÊTE entre deux cases (portes), qui n'occupent aucune case.
func _register() -> void:
	_dungeon.register_mechanism(cell, self)

## Désenregistrement, symétrique de [method _register].
func _unregister() -> void:
	_dungeon.unregister_mechanism(cell, self)

## Hook d'init des sous-classes, appelé une fois la case connue et l'enregistrement fait.
func _on_registered() -> void:
	pass

## Repère visuel du mécanisme (placeholder de test). Surchargé par les sous-classes pour
## poser un marqueur coloré identifiable en fenêtre. Défaut : aucun.
func _spawn_visual() -> void:
	pass

## Marqueur visuel du mécanisme (créé par [method _add_marker]).
var _marker: MeshInstance3D
## Hauteur du marqueur, en mètres — sert à le reposer au sol quand on l'aplatit.
var _marker_height := 0.0

## Pose un marqueur (boîte colorée) sur la case du mécanisme. `height`/`size` en MÈTRES
## (une case fait [constant DungeonManager.CELL_SIZE] = 1 m). L'origine du nœud est au sol
## de la case ([method DungeonManager.cell_to_world]) : le marqueur est simplement posé dessus.
func _add_marker(color: Color, height := 0.6, size := 0.7) -> MeshInstance3D:
	return _add_marker_box(color, Vector3(size, height, size))

## Variante à dimensions libres (portes : fines dans un axe) avec décalage local optionnel —
## utile pour poser un visuel sur l'arête de la case plutôt qu'en son centre.
func _add_marker_box(color: Color, size: Vector3, offset := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mi.material_override = mat
	mi.position = offset + Vector3(0.0, size.y * 0.5, 0.0)
	add_child(mi)
	_marker = mi
	_marker_height = size.y
	return mi

## Facteur d'écrasement d'un marqueur aplati (épuisé, ou porte ouverte).
const FLATTENED := 0.08

## Gris sombre mat d'un mécanisme épuisé : net contraste avec sa couleur active, et aucune
## émission (un mécanisme actif s'éclaire souvent lui-même).
const SPENT_COLOR := Color(0.24, 0.24, 0.27)

## Grise et aplatit le marqueur pour signaler un mécanisme ÉPUISÉ (piège déclenché, coffre
## ouvert…) : reste visible (règle doc) mais clairement inerte, presque au niveau du sol.
func _mark_spent() -> void:
	_grey_marker()
	_flatten_marker(true)

## Grise le marqueur SANS l'aplatir — pour un mécanisme épuisé dont la FORME porte encore une
## information (le dé, qui garde la face sortie tournée vers le joueur).
func _grey_marker() -> void:
	if _marker == null:
		return
	var mat := StandardMaterial3D.new()  # matériau neuf : coupe aussi l'émission de l'état actif
	mat.albedo_color = SPENT_COLOR
	_marker.material_override = mat

## Retire le marqueur — pour un mécanisme qui ne laisse RIEN derrière lui (litière recyclée :
## la case redevient un sol ordinaire, y dessiner encore un tas serait mentir).
func _remove_marker() -> void:
	if _marker == null:
		return
	_marker.queue_free()
	_marker = null
	_marker_height = 0.0

## Reconstruit le marqueur dans son état ACTIF (réarmement entre deux visites).
func _respawn_marker() -> void:
	_remove_marker()
	_spawn_visual()

## Aplatit (ou redresse) le marqueur en le gardant posé sur le sol de la case.
func _flatten_marker(flat: bool) -> void:
	if _marker == null:
		return
	var f := FLATTENED if flat else 1.0
	_marker.scale.y = f
	_marker.position.y = _marker_height * f * 0.5

# --------------------------------------------------------------------------
# Hooks du framework (surchargés par les sous-classes ; défauts neutres)
# --------------------------------------------------------------------------

## Le mécanisme est-il ÉPUISÉ (plus rien à en tirer : piège déclenché, coffre vidé, dé roulé,
## cristal utilisé…) ? Règle transverse : ce qui n'est plus actionnable ne doit plus se
## présenter comme actif — ni en 3D (marqueur grisé, cf. [method _mark_spent]) ni sur la carte
## ([ExplorationMinimap] assombrit ces mécanismes). Défaut : jamais épuisé (portes,
## ascenseurs, ponts, murs — réutilisables sans fin).
func is_spent() -> bool:
	return false

## Ce mécanisme figure-t-il sur la MINI-MAP ? Doc « User Interface » : la carte montre les
## mécanismes de l'étage courant, mais PAS les pièges — les révéler d'avance viderait leur rôle.
## Défaut : oui (une porte, un coffre, un escalier sont des repères de navigation).
func shows_on_map() -> bool:
	return true

## La case est-elle infranchissable de par ce mécanisme ? (gate fermée, obstacle…)
## Consulté par [method DungeonManager.is_walkable] et le pas du joueur.
func blocks_walk() -> bool:
	return false

## Ce mécanisme coupe-t-il la VUE ? Par défaut, ce qui barre le passage barre aussi la vue (un
## mur, une porte fermée) ; une rambarde, basse, fait exception. Sert à interdire les actions
## sur ce qui se trouve DERRIÈRE un obstacle opaque : on n'agit pas sur ce qu'on ne voit pas.
func blocks_sight() -> bool:
	return blocks_walk()

## Un acteur (joueur/rival) vient d'entrer sur la case. Point d'activation des pièges,
## coffres, téléporteurs, ascenseurs…
func on_enter(_who: Node) -> void:
	pass

## Cadence par tour, diffusée par [method DungeonManager.advance_turn] (gate automatisée…).
func on_turn(_turn: int) -> void:
	pass

## Actions contextuelles quand l'acteur est SUR la case (ex. Dig sur sol friable).
## Réservé à la future surface d'actions d'exploration (incrément Special Grounds).
func on_tile_actions(_who: Node) -> Array:
	return []

## Actions contextuelles quand l'acteur est ADJACENT et orienté vers la case (ex. Recycle,
## Meditate, Refresh Crystal). `facing` = delta de case regardé.
func on_adjacent_actions(_who: Node, _facing: Vector3i) -> Array:
	return []

# --- Changement d'étage (escaliers, ascenseurs, et ce qu'on inventera ensuite) ---
#
# Interface commune consultée par la POURSUITE des rivaux : quand le joueur passe à un autre
# étage, un rival cherche par où l'y rejoindre. Plutôt que de connaître chaque mécanisme, il
# interroge ces trois hooks. Un mécanisme qui ne mène nulle part garde les défauts.

## Ce mécanisme fait-il passer d'un étage à l'autre ?
func has_level_link() -> bool:
	return false

## Case depuis laquelle on l'emprunte : la case d'abord pour un escalier (on y est adjacent et
## on entre dedans), la plateforme elle-même pour un ascenseur (y monter suffit).
func level_link_from() -> Vector3i:
	return cell

## Case d'arrivée du passage.
func level_link_to() -> Vector3i:
	return cell

## Faut-il ENTRER dans la case du mécanisme depuis [method level_link_from] (escalier), ou bien
## le simple fait d'arriver sur cette case déclenche-t-il le passage (ascenseur) ?
func level_link_needs_step_in() -> bool:
	return false

## Réinitialisation à l'entrée d'un donjon (persistance entre visites). Défaut : rien.
func reset_between_visits() -> void:
	pass

func _exit_tree() -> void:
	if _dungeon:
		_unregister()
