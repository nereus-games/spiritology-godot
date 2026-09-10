## Vérification headless de la géométrie du donjon : échelle (case = 1 m, yeux à 0.6 m),
## dalles minces (on marche sous un étage), portes posées sur les arêtes. Passe tous les
## scénarios de test en revue et sort en code 1 si l'un d'eux régresse.
##
## Lancé par : Godot --headless --path . res://scenes/dev/geometry_check.tscn
## (scène de démarrage, et non --script : en mode --script les autoloads n'existent pas encore
## et les scripts d'exploration qui les référencent ne compilent pas.)
extends Node

const ScenarioCatalog := preload("res://scripts/dev/scenario_catalog.gd")
const EXPLORATION := preload("res://scenes/exploration/exploration.tscn")
const RIVAL_SCENE := preload("res://scenes/exploration/rival/rival.tscn")

var _fails: Array[String] = []


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  OK   %s" % label)
	else:
		print("  FAIL %s" % label)
		_fails.append(label)


func _ready() -> void:
	_run_all()


func _run_all() -> void:
	await get_tree().process_frame  # laisse les autoloads et la racine s'installer
	# Balayage du CATALOGUE, et non d'une liste figée : un scénario ajouté à
	# `data/scenarios/` est vérifié d'office, et s'il n'a pas de constructeur,
	# ScenarioCatalog.build() le signale au lieu de retomber en silence sur un autre.
	for scenario in ScenarioCatalog.list():
		await _run_scenario(scenario.id)
	print("")
	if _fails.is_empty():
		print("TOUT OK")
	else:
		print("ÉCHECS : %s" % [_fails])
	get_tree().quit(0 if _fails.is_empty() else 1)


func _run_scenario(id: StringName) -> void:
	print("[%s]" % id)
	ScenarioCatalog.selected_id = id
	var scene = EXPLORATION.instantiate()
	get_tree().root.add_child(scene)
	await get_tree().process_frame  # _ready de la scène (grille bâtie, mécanismes enregistrés)
	var dm = scene.get_node("DungeonManager")
	var player = scene.get_node("Player")

	# Échelle : bloc de mur = 1 m³, yeux sous le haut du mur.
	_check(dm.CELL_SIZE == 1.0, "case = 1 m")
	var cam_rig = player.get_node("CameraRig")
	var eye_y: float = player.global_position.y + cam_rig.position.y
	var floor_y: float = dm.cell_to_world(player.cell).y
	_check(
		is_equal_approx(eye_y - floor_y, dm.EYE_HEIGHT), "yeux à %.2f m du sol" % (eye_y - floor_y)
	)
	_check(eye_y - floor_y < dm.CELL_SIZE, "yeux sous le haut des murs")

	# Géométrie générée : dalles minces (plafonds franchissables) et blocs de mur pleins.
	var slabs := 0
	var walls := 0
	var misplaced := 0
	var too_thick := 0
	for child in dm.get_children():
		var mi := child as MeshInstance3D
		if mi == null or not (mi.mesh is BoxMesh):
			continue
		var s: Vector3 = mi.mesh.size
		if not is_equal_approx(s.x, dm.CELL_SIZE):
			continue  # visuel de mécanisme, pas de la grille
		var top: float = mi.position.y + s.y * 0.5
		if is_equal_approx(s.y, dm.FLOOR_THICKNESS):
			slabs += 1
			# Face haute au niveau du sol d'un étage (ou d'une fosse, décalée de PIT_DEPTH).
			if not (_on_level(top, dm.CELL_SIZE) or _on_level(top + dm.PIT_DEPTH, dm.CELL_SIZE)):
				misplaced += 1
		elif is_equal_approx(s.y, dm.CELL_SIZE):
			walls += 1
			# Le bloc remplit le volume de SA case, sans mordre sur l'étage du dessus.
			if not _on_level(top, dm.CELL_SIZE):
				misplaced += 1
		else:
			too_thick += 1
	_check(
		slabs > 0,
		"%d dalles minces (sol = plafond franchissable) + %d blocs de mur 1 m³" % [slabs, walls]
	)
	_check(misplaced == 0, "toutes les dalles/murs alignés sur leur étage")
	_check(too_thick == 0, "aucun sol rendu comme un bloc plein")
	_check_no_double_ground(dm, slabs)

	if id == &"movement":
		await _check_bottomless(dm, player)
		_check_rival_sprite_box(dm)
	if id == &"traps":
		_check_traps_hidden_on_map(dm)
		_check_disarray_mouse(player)
	if id == &"gates":
		await _check_gates(dm, player)
	if id == &"stairs":
		await _check_stairs(dm, player)
	if id == &"bridge":
		_check_bridge(dm)
		_check_bridge_disarray(scene, dm, player)
	if id == &"bridge_rival":
		_check_bridge(dm)
		await _check_rival_on_bridge(dm)

	scene.queue_free()
	# Purge : le prochain scénario doit repartir d'un donjon vide.
	get_tree().root.remove_child(scene)
	scene.free()


## Rambardes (doc « Walls + Decors » / Guardrails) : posées sur l'arête comme une porte qui ne
## s'ouvre jamais, elles empêchent de franchir un bord d'étage SANS combler le vide derrière et
## sans coûter de case. Le même bord, deux cases plus loin, reste ouvert (et fait tomber).
func _check_guardrails(dm) -> void:
	var edge := Vector3i(1, 0, 0)
	var railed := Vector3i(6, 4, 4)  # bord est protégé
	var open_edge := Vector3i(6, 4, 6)  # même bord, deux pas plus loin : rien
	var rails: Array = dm.edge_mechanisms_between(railed, railed + edge)
	_check(rails.size() == 1, "rambarde posée sur l'arête du bord est")
	_check(
		dm.mechanisms_at(railed).is_empty() and dm.mechanisms_at(railed + edge).is_empty(),
		"une rambarde n'occupe aucune case"
	)
	_check(
		dm.is_floor(railed) and dm.is_walkable(railed),
		"la case derrière la rambarde reste praticable"
	)
	_check(
		dm.is_edge_blocked(railed, railed + edge) and dm.is_edge_blocked(railed + edge, railed),
		"bord protégé : franchissement refusé dans les deux sens"
	)
	_check(
		dm.fall_landing(railed + edge) != railed + edge,
		"le vide est toujours là derrière la rambarde (elle ne comble rien)"
	)
	_check(
		not dm.is_edge_blocked(open_edge, open_edge + edge),
		"deux cases plus loin, le même bord est ouvert"
	)
	_check(
		dm.fall_landing(open_edge + edge) == Vector3i(7, 0, 6),
		"et il fait tomber jusqu'en bas (4 unités)"
	)
	_check_rival_stopped_by_rail(dm)
	if rails.size() == 1:
		_check(
			rails[0].HEIGHT < dm.EYE_HEIGHT,
			(
				"rambarde plus basse que les yeux (%.2f m < %.2f m) : ne coupe pas la vue"
				% [rails[0].HEIGHT, dm.EYE_HEIGHT]
			)
		)


## Une rambarde retient aussi les RIVAUX : un rival qui voudrait sauter pour poursuivre ne peut
## pas enjamber le bord protégé — il lui faut un bord ouvert.
func _check_rival_stopped_by_rail(dm) -> void:
	var post := Vector3i(6, 4, 4)  # derrière la rambarde du bord est
	var below := Vector3i(7, 0, 4)  # ce qu'il viserait en sautant par-dessus
	var rival = RIVAL_SCENE.instantiate()
	rival.position = dm.cell_to_world(post)
	dm.add_child(rival)
	var brink: Vector3i = rival._open_drop_edge(below)
	_check(
		brink != post + Vector3i(1, 0, 0),
		"le rival ne saute pas par-dessus la rambarde (bord choisi : %s)" % brink
	)
	rival.queue_free()


## Doc « Walls + Decors » : un bloc de mur peut servir de sol à l'étage au-dessus. Une case de
## sol posée sur un mur ne doit donc PAS recevoir de dalle en plus (sinon deux faces hautes
## exactement coplanaires : géométrie doublée et z-fighting). On vérifie le compte exact de
## dalles attendu : sols hors fosse sans mur dessous, plus le fond des fosses qui ne surplombent
## rien.
func _check_no_double_ground(dm, slabs: int) -> void:
	var walls: Dictionary = dm.derive_wall_cells()
	var expected := 0
	var on_walls := 0
	for c in dm._floor:
		if dm._pit.has(c):
			continue
		if walls.has(c + Vector3i.DOWN):
			on_walls += 1
		else:
			expected += 1
	for c in dm._pit:
		if dm.fall_landing(c) == c:
			expected += 1
	_check(
		slabs == expected,
		(
			"%d dalle(s) attendue(s), %d rendue(s) — %d sol(s) portés par un mur, sans dalle"
			% [expected, slabs, on_walls]
		)
	)


## `v` tombe-t-il sur un multiple de `step` (à l'erreur flottante près, y compris juste en
## dessous — fposmod y renvoie presque `step` et non presque 0) ?
func _on_level(v: float, step: float) -> bool:
	var r := fposmod(v, step)
	return minf(r, step - r) < 0.001


## Doc « User Interface » : la mini-map ne montre pas les pièges. Un piège n'y figure qu'une
## fois CONNU (révélé, ou déclenché) — les scénarios de test, eux, les posent révélés.
## Disarray et regard libre. La doc ne fait plus d'exception pour la caméra libre : un geste de
## souris est dévié d'un quart de tour, à AMPLITUDE inchangée (pour ne pas valider une rotation
## que le joueur n'a pas voulue). Mais il ne DÉCOMPTE le piège que s'il enclenche vraiment une
## rotation — sinon on purgerait le disarray en agitant le curseur, sans dépenser un seul tour.
func _check_disarray_mouse(player) -> void:
	var handler = player.get_node("PlayerInputHandler")
	var aff = player.affliction
	while aff.has_disarray():
		aff.consume_move()
	aff.add_disarray(30)
	# Aucun de ces gestes ne consomme : ils consultent tous la MÊME entrée de tête. On l'amène
	# donc sur une entrée déviée, sinon le test dépend du mélange de la file.
	while aff.has_disarray() and not aff.peek_move():
		aff.consume_move()
	_check(aff.peek_move(), "file amenée sur un mouvement dévié")

	# --- Gestes SANS rotation enclenchée : déviés, mais gratuits ---
	var gesture := Vector2(12.0, -5.0)  # trop court pour franchir commit_angle
	var before: int = aff.remaining_disarray()
	var deviated := 0
	var bad_length := 0
	var bad_angle := 0
	var unstable := 0
	for i in range(24):
		var first: Vector2 = handler._disarrayed_mouse(gesture)
		# Deuxième événement du MÊME geste : le curseur tourne, le décalage ne bouge pas.
		var second: Vector2 = handler._disarrayed_mouse(gesture)
		if not first.is_equal_approx(second):
			unstable += 1
		if not is_equal_approx(first.length(), gesture.length()):
			bad_length += 1
		if not first.is_equal_approx(gesture):
			deviated += 1
			if int(roundf(rad_to_deg(gesture.angle_to(first)))) % 90 != 0:
				bad_angle += 1
		handler._process(handler.MOUSE_BURST_IDLE + 0.01)  # le curseur s'arrête : geste clos
	_check(unstable == 0, "le décalage tient tout le geste (curseur tourné en cours de route)")
	_check(bad_length == 0, "amplitude du geste inchangée (pas de rotation involontaire)")
	_check(
		deviated == 24, "les 24 gestes sont déviés (%d) — l'entrée de tête ne bouge pas" % deviated
	)
	_check(bad_angle == 0, "toute déviation est un quart de tour (90 / 180 / 270°)")
	_check(
		aff.remaining_disarray() == before,
		"24 gestes sans rotation : rien décompté (%d)" % aff.remaining_disarray()
	)

	# --- Geste QUI enclenche une rotation : là, ça compte pour un mouvement ---
	# Diagonale assez ample pour franchir commit_angle sur l'axe du lacet quel que soit le
	# quart de tour tiré (une déviation ne doit pas offrir une rotation gratuite).
	var sweep := Vector2(400.0, 400.0)
	var turns := 0
	var spent_wrong := 0
	for i in range(8):
		handler._yaw_offset = 0.0  # chaque balayage part du neutre (sinon le reliquat décide)
		var turn_before: int = _dungeon_turn(player)
		var left: int = aff.remaining_disarray()
		handler._apply_mouse_look(sweep)
		handler._process(0.016)  # _fold_offset valide la rotation
		var committed: int = _dungeon_turn(player) - turn_before
		turns += committed
		if aff.remaining_disarray() != left - committed:
			spent_wrong += 1
		handler._process(handler.MOUSE_BURST_IDLE + 0.01)  # geste suivant
	_check(turns == 8, "chaque balayage ample enclenche une rotation (%d/8)" % turns)
	_check(spent_wrong == 0, "une rotation enclenchée = un mouvement de disarray retiré")

	# --- Disarray épuisé : le regard libre redevient franc ---
	while aff.has_disarray():
		aff.consume_move()
	handler._process(handler.MOUSE_BURST_IDLE + 0.01)
	_check(
		handler._disarrayed_mouse(gesture).is_equal_approx(gesture),
		"disarray épuisé : le geste n'est plus dévié"
	)


## Numéro de tour courant, lu depuis le donjon auquel le joueur est rattaché.
func _dungeon_turn(player) -> int:
	return player.get_parent().get_node("DungeonManager").turn_count


func _check_traps_hidden_on_map(dm) -> void:
	var shown := 0
	var traps := 0
	for m in dm.get_children():
		if not (m is Node) or not m.has_method("shows_on_map") or m.get("kind") == null:
			continue
		if not "revealed" in m:
			continue
		traps += 1
		if m.shows_on_map():
			shown += 1
		m.revealed = false
		_check(not m.shows_on_map(), "piège caché : absent de la carte")
		m.revealed = true
		_check(m.shows_on_map(), "piège connu : présent sur la carte")
	_check(traps > 0 and shown == traps, "%d piège(s) du scénario de test, tous révélés" % traps)


## Charte « Visuals + Sounds » : un sprite de rival tient dans 90 cm × 90 cm. On l'éprouve sur
## une espèce PLUS LARGE QUE HAUTE (jézal, 2000 × 1898) : caler sur la seule hauteur la ferait
## déborder sur les cases voisines.
func _check_rival_sprite_box(dm) -> void:
	for species in [&"jezal", &"jezal", &"fliritus", &"ravbak"]:
		var rival = RIVAL_SCENE.instantiate()
		rival.species_id = species
		rival.position = dm.cell_to_world(Vector3i(0, 0, 0))
		dm.add_child(rival)
		var sprite := rival.get_node_or_null("Sprite3D") as Sprite3D
		if sprite != null and sprite.texture != null:
			var w: float = sprite.texture.get_width() * sprite.pixel_size
			var h: float = sprite.texture.get_height() * sprite.pixel_size
			_check(
				w <= rival.world_height + 0.001 and h <= rival.world_height + 0.001,
				"sprite %s : %.2f × %.2f m, tient dans %.2f m" % [species, w, h, rival.world_height]
			)
			_check(is_equal_approx(sprite.position.y, h * 0.5), "sprite %s posé au sol" % species)
		rival.queue_free()


## Chute SANS FOND : elle ne devrait pas exister — une case sans rien en dessous est rendue en
## mur. Mais si le level design marque un trou franc, entrer dedans dévitalise le duo (un sol
## qu'on n'atteint jamais est un sol trop bas pour qu'on y survive) au lieu de bloquer en
## silence.
func _check_bottomless(dm, player) -> void:
	var hole := Vector3i(3, 0, -1)  # devant le départ : normalement un mur de pourtour
	var plain := Vector3i(2, 0, -1)  # même rangée, laissée telle quelle
	_check(not dm.is_bottomless(plain), "case simplement absente = mur (pas de chute)")
	dm.mark_hole(hole)
	_check(dm.is_bottomless(hole), "trou franc = chute sans fond")
	_check(not dm.derive_wall_cells().has(hole), "un trou franc n'est pas bouché par un mur")
	var wiped := [false]
	GameSession.party_wiped.connect(func() -> void: wiped[0] = true, CONNECT_ONE_SHOT)
	await player.fall_forever(hole)
	_check(wiped[0], "chute sans fond : duo dévitalisé (donc sorti du donjon)")


## Portes : sur l'arête, les deux cases restent praticables, le passage est barré tant que
## la porte est fermée, et l'action est offerte des deux côtés.
func _check_gates(dm, player) -> void:
	var a := Vector3i(1, 0, 3)
	var b := Vector3i(1, 0, 4)
	_check(dm.is_floor(a) and dm.is_floor(b), "les 2 cases autour d'une porte sont du sol")
	_check(
		dm.mechanisms_at(a).is_empty() and dm.mechanisms_at(b).is_empty(),
		"une porte n'occupe aucune case"
	)
	var gate = dm.edge_mechanisms_between(a, b)[0]
	_check(gate != null, "porte trouvée sur l'arête")
	_check(dm.edge_mechanisms_between(b, a).size() == 1, "arête symétrique (mêmes 2 sens)")
	# Porte verrouillée (fermée) : barre le passage dans les deux sens, laisse les cases libres.
	var la := Vector3i(1, 0, 6)
	var lb := Vector3i(1, 0, 7)
	_check(
		dm.is_edge_blocked(la, lb) and dm.is_edge_blocked(lb, la), "porte fermée : passage barré"
	)
	_check(dm.is_walkable(la) and dm.is_walkable(lb), "porte fermée : cases toujours praticables")
	_check(not dm.can_step(la, lb), "can_step refuse de traverser une porte fermée")
	# Actions accessibles des deux côtés (ouvrir / méditer).
	var from_south: Array = dm.actions_for(la, Vector3i(0, 0, 1), player)
	var from_north: Array = dm.actions_for(lb, Vector3i(0, 0, -1), player)
	_check(
		from_south.size() == 1 and from_south[0].id == &"open_gate", "action « ouvrir » côté sud"
	)
	_check(
		from_north.size() == 1 and from_north[0].id == &"open_gate", "action « ouvrir » côté nord"
	)
	# Ouverture : le passage se libère.
	var locked = dm.edge_mechanisms_between(la, lb)[0]
	# Le prix est ANNONCÉ par la porte, sur ses deux faces (doc : « shown on the gate itself »,
	# « on both sides, at eye level ») — sinon le joueur devrait payer pour savoir combien.
	_check_locked_gate_price(locked)
	_check(locked.try_open_locked(), "paiement de la porte verrouillée")
	_check(dm.can_step(la, lb) and dm.can_step(lb, la), "porte ouverte : passage libre des 2 côtés")
	var cleared := true
	for child in locked.get_children():
		if child is Label3D and child.text != "":
			cleared = false
	_check(cleared, "porte ouverte : le prix n'est plus affiché")
	# Ce qui coupe la vue coupe l'interaction : le tas posé DERRIÈRE la porte de méditation
	# fermée n'est pas actionnable ; la porte, elle, propose toujours « méditer ».
	var mz := Vector3i(1, 0, 9)
	var toward := Vector3i(0, 0, 1)
	_check(dm.is_edge_opaque(mz, mz + toward), "porte fermée : arête opaque")
	var ids := _action_ids(dm.actions_for(mz, toward, player))
	_check(ids == [&"meditate"], "derrière une porte fermée : aucune action du décor (%s)" % [ids])
	_check_meditation_streak(dm, player)
	# Porte ouverte : le tas redevient visible, donc actionnable.
	_check(not dm.is_edge_opaque(mz, mz + toward), "porte ouverte : arête transparente")
	var after := _action_ids(dm.actions_for(mz, toward, player))
	_check(
		&"examine" in after or &"recycle" in after,
		"porte ouverte : les actions du décor derrière reviennent (%s)" % [after]
	)


## Une porte verrouillée affiche son prix sur CHAQUE face, à hauteur des yeux, tant qu'elle est
## fermée — et n'a plus rien à dire une fois ouverte.
func _check_locked_gate_price(locked) -> void:
	var labels := []
	for child in locked.get_children():
		if child is Label3D:
			labels.append(child)
	_check(labels.size() == 2, "prix inscrit sur les 2 faces de la porte (%d)" % labels.size())
	var expected := (
		"%d × %s" % [locked.locked_cost(), tr(GameData.object(locked.cost_currency).name_key())]
	)
	var shown := true
	for label in labels:
		if label.text != expected:
			shown = false
		_check(
			absf(label.position.y - DungeonManager.EYE_HEIGHT) < 0.01,
			"prix à hauteur des yeux (y = %.2f m)" % label.position.y
		)
	_check(shown, "prix lisible sur les 2 faces (« %s »)" % expected)


func _action_ids(actions: Array) -> Array:
	var ids := []
	for a in actions:
		ids.append(a.id)
	return ids


## Porte de méditation : doc « 3 CONSECUTIVE times in front of them » — la série ne compte que
## si le joueur tient son poste ; bouger ou se détourner la remet à zéro.
func _check_meditation_streak(dm, _player) -> void:
	var ma := Vector3i(1, 0, 9)
	var toward := Vector3i(0, 0, 1)
	var gate = dm.edge_mechanisms_between(ma, ma + toward)[0]
	# Le joueur est ailleurs pendant ce test : c'est justement ce qui doit rompre la série.
	_check(not gate.meditate(ma, toward), "1re méditation : porte encore fermée")
	_check(not gate.meditate(ma, toward), "2e méditation : porte encore fermée")
	gate.on_turn(1)  # un tour s'écoule alors que le joueur n'est pas au poste -> série rompue
	_check(not gate.is_open(), "série rompue : la porte ne s'ouvre pas")
	_check(not gate.meditate(ma, toward), "après rupture, on repart de 1/3")
	_check(not gate.meditate(ma, toward), "2/3")
	_check(gate.meditate(ma, toward), "3 méditations consécutives : porte ouverte")
	# L'arête est libérée. (La case au-delà porte un tas, obstacle : c'est LUI qui bloque
	# maintenant, plus la porte.)
	_check(not dm.is_edge_blocked(ma, ma + toward), "porte de méditation ouverte : arête libérée")


## Pont étroit : chaque planche surplombe un vrai sol (une chute atterrit quelque part, avec
## les dégâts normaux ∝ profondeur), et la remontée depuis le fond ramène bien sur du sol.
func _check_bridge(dm) -> void:
	var planks := []
	for child in dm.get_children():
		if child.has_method("engage") and child.has_method("direction"):
			planks.append(child.cell)
	_check(planks.size() > 0, "%d cases de pont" % planks.size())
	var landed := 0
	var depth := 0
	for c in planks:
		var landing: Vector3i = dm.fall_landing(c)
		if landing != c and landing.y < c.y:
			landed += 1
			depth = maxi(depth, c.y - landing.y)
	_check(
		landed == planks.size(),
		(
			"chaque planche surplombe un sol (%d/%d, ravin de %d étages)"
			% [landed, planks.size(), depth]
		)
	)
	_check(depth >= 2, "ravin de plus d'un étage (dégâts de chute ∝ profondeur)")
	# Remontée : chaque volée montante part d'une case praticable et arrive sur du sol.
	var flights := 0
	for child in dm.get_children():
		if not child.has_method("stairs_destination") or child.level_delta <= 0:
			continue
		flights += 1
		var from: Vector3i = child.cell - child.face_dir  # case d'où l'on aborde la volée
		var dest: Vector3i = child.stairs_destination(from, child.face_dir)
		_check(
			dm.is_walkable(from) and dm.is_floor(dest),
			"volée %s : %s -> %s praticable" % [child.cell, from, dest]
		)
	_check(flights >= 2, "%d volées pour remonter du fond au départ" % flights)


## Le pont décompte le disarray case par case (une case franchie EST un mouvement), et la
## case d'arrivée n'a d'autre issue que le pont — sinon on gaspillerait le disarray à errer
## sur une plateforme au lieu de tester le pont sous disarray.
func _check_bridge_disarray(scene, dm, player) -> void:
	var arrival := Vector3i(1, 2, 7)
	_check(dm.is_floor(arrival), "case d'arrivée %s" % arrival)
	var ways_out := 0
	for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		if dm.is_walkable(arrival + d):
			ways_out += 1
	_check(ways_out == 1, "arrivée murée : %d issue (le pont)" % ways_out)

	# Une case de pont franchie consomme un mouvement de disarray.
	var first := Vector3i(1, 2, 2)
	var bridge = null
	for m in dm.mechanisms_at(first):
		if m.has_method("engage"):
			bridge = m
	if bridge == null:
		_check(false, "mécanisme de pont en %s" % first)
		return
	bridge.engage(Vector3i(0, 0, 1), false)
	scene._active_bridge = bridge
	scene._bridge_from = first
	scene._bridge_dir = Vector3i(0, 0, 1)
	player.affliction.add_disarray(5)
	var before: int = player.affliction.remaining_disarray()
	scene._advance_bridge_cell(player)
	var after: int = player.affliction.remaining_disarray()
	_check(
		after == before - 1, "une case de pont décompte le disarray (%d -> %d)" % [before, after]
	)


## Règles « rivaux » des ponts étroits (doc) : test d'équilibre simplifié tiré à la création,
## chute vers le sol du dessous avec dégâts, dévitalisation sur la carte, et croisement de
## deux rivaux sur une planche = double chute sur deux cases distinctes.
func _check_rival_on_bridge(dm) -> void:
	var rivals: Array = dm.rivals()
	_check(rivals.size() == 1, "%d rival sur la carte" % rivals.size())
	if rivals.is_empty():
		return
	var r = rivals[0]
	_check(
		r.bridge_fall_chance >= 0.01 and r.bridge_fall_chance <= 0.02,
		"probabilité de chute tirée dans 1-2 %% (%.2f %%)" % (r.bridge_fall_chance * 100.0)
	)
	_check(r.den == r.max_den, "DEN de carte plein au départ (%d)" % r.den)

	# Chute depuis une planche : atterrit au fond du ravin et encaisse 2 étages.
	var plank := Vector3i(1, 2, 4)
	_check(dm.is_narrow_bridge(plank), "case %s reconnue comme planche" % plank)
	dm.release(r.cell)
	dm.reserve(plank, r)
	r.cell = plank
	var den_before: int = r.den
	var alive: bool = r.fall_down(plank)
	var expected: int = dm.fall_damage(2)  # doc : 2 unités de hauteur = 10 DEN
	_check(alive and r.cell.y == 0, "le rival tombe au fond du ravin (%s)" % r.cell)
	_check(
		den_before - r.den == expected,
		"dégâts de chute du rival = %d DEN sur 2 étages (%d -> %d)" % [expected, den_before, r.den]
	)

	# Dévitalisé par une chute : dissous sur la carte, sans rencontre.
	r.apply_map_damage(r.max_den)
	await get_tree().process_frame
	_check(
		dm.rivals().is_empty() and not is_instance_valid(r),
		"un rival dévitalisé par la chute est dissous (sans rencontre)"
	)

	# Croisement de deux rivaux sur une planche : les deux tombent, sur deux cases distinctes.
	var a = ScenarioCatalog._spawn_rival(dm, &"ravbak", Vector3i(1, 2, 3))
	var b = ScenarioCatalog._spawn_rival(dm, &"ravbak", Vector3i(1, 2, 5))
	await get_tree().process_frame
	b._collide_with_rival(Vector3i(1, 2, 3), a)
	_check(a.cell.y == 0 and b.cell.y == 0, "les deux rivaux tombent (%s / %s)" % [a.cell, b.cell])
	_check(a.cell != b.cell, "ils atterrissent sur deux cases distinctes")

	# Poursuite d'un CHANGEMENT D'ÉTAGE : le joueur remonte au départ, le rival le suit par
	# les deux volées d'escalier (moyen gratuit : aucune hésitation, contrairement à la chute).
	var chaser = ScenarioCatalog._spawn_rival(dm, &"ravbak", Vector3i(2, 0, 5))
	await get_tree().process_frame
	chaser.move_duration = 0.0
	var top := Vector3i(3, 2, 0)
	chaser.witness_player_level_change(Vector3i(3, 0, 5), top)
	var turns_used := 0
	for i in range(20):
		chaser.take_turn(top)
		for f in range(3):
			await get_tree().process_frame
		turns_used += 1
		if chaser.cell.y == top.y:
			break
	_check(
		chaser.cell.y == top.y,
		(
			"un rival suit le joueur d'un étage à l'autre par l'escalier (%s en %d tours)"
			% [chaser.cell, turns_used]
		)
	)


## Multi-étages : on marche SOUS les gradins, le barème de chute de la doc est respecté aux
## quatre hauteurs, et les deux formes d'ascenseur font l'aller-retour avec leur passager.
func _check_stairs(dm, player) -> void:
	# Pilier : la case (1,0,8) a été retirée de l'étage 0, elle est donc rendue en bloc de mur —
	# et c'est ce mur qui porte le sol de la case du dessus, sans dalle supplémentaire.
	var pillar := Vector3i(1, 0, 8)
	var carried := pillar + Vector3i.UP
	var walls: Dictionary = dm.derive_wall_cells()
	_check(walls.has(pillar), "case retirée rendue en bloc de mur (pilier)")
	_check(not dm.is_floor(pillar) and dm.is_floor(carried), "sol praticable posé sur le pilier")
	_check(
		dm.cell_to_world(carried).y == dm.cell_to_world(pillar).y + dm.CELL_SIZE,
		"le sol porté est exactement à la face haute du mur"
	)

	_check_guardrails(dm)

	var under := Vector3i(3, 0, 6)
	var above := Vector3i(3, 1, 6)
	_check(dm.is_walkable(under), "case praticable sous le gradin")
	_check(dm.is_floor(above), "gradin au-dessus de cette case")
	var headroom: float = dm.cell_to_world(above).y - dm.FLOOR_THICKNESS - dm.cell_to_world(under).y
	_check(headroom > dm.EYE_HEIGHT, "dégagement sous plafond = %.2f m > yeux" % headroom)
	var levels := 0
	for y in range(0, 6):
		if dm.is_floor(Vector3i(6, y, 12)):
			levels += 1
	_check(levels == 5, "%d étages empilés" % levels)

	# Un ESCALIER par palier : c'est le chemin de secours. Un ascenseur reste où on l'a laissé,
	# donc sans volée doublant chaque saut d'étage, une chute pourrait rendre le haut
	# définitivement inatteignable.
	var by_level := {}
	for m in dm.get_children():
		if not m.has_method("stairs_destination") or m.level_delta <= 0:
			continue
		var from: Vector3i = m.level_link_from()
		var to: Vector3i = m.level_link_to()
		if dm.is_walkable(from) and dm.is_floor(to) and to.y == from.y + 1:
			by_level[from.y] = true
	var missing := []
	for y in range(0, 4):
		if not by_level.has(y):
			missing.append(y)
	_check(
		missing.is_empty(),
		"une volée praticable pour chaque palier 0→1→2→3→4 (manquants : %s)" % [missing]
	)

	# Barème de la doc : « 2+ height units → 10 damage, plus 5 per additional unit ».
	for pair in [[1, 0], [2, 10], [3, 15], [4, 20]]:
		_check(
			dm.fall_damage(pair[0]) == pair[1],
			"chute de %d unité(s) : %d DEN (%d)" % [pair[0], pair[1], dm.fall_damage(pair[0])]
		)

	# Les quatre hauteurs doivent être atteignables : colonne EST (x = 6), rien n'arrête avant
	# l'étage 0. Sortir du gradin y doit faire tomber de y unités.
	for y in range(1, 5):
		var landing: Vector3i = dm.fall_landing(Vector3i(7, y, 8))
		_check(
			landing == Vector3i(7, 0, 8),
			"sortir du gradin %d côté est = chute de %d unités (%s)" % [y, y, landing]
		)
	# Côté OUEST, chaque gradin surplombe le suivant : une seule unité, donc aucun dégât.
	_check(
		dm.fall_landing(Vector3i(1, 2, 8)) == Vector3i(1, 1, 8),
		"sortir d'un gradin côté ouest = chute d'1 unité (indolore)"
	)

	# Ascenseurs : un vertical, un à trajet complexe (segments sur les trois axes).
	var lifts := []
	for m in dm.get_children():
		if m.has_method("ride"):
			lifts.append(m)
	_check(lifts.size() == 2, "%d ascenseurs" % lifts.size())
	var winding = null
	for m in lifts:
		if m.path.size() == 1:
			_check(m.far_end().y != m.cell.y, "ascenseur %s : trajet vertical" % m.cell)
		elif m.path.size() > 1:
			winding = m
	if winding == null:
		_check(false, "un ascenseur au trajet complexe")
	else:
		var axes := {}
		var prev: Vector3i = winding.cell
		for wp in winding.path:
			var d: Vector3i = wp - prev
			if d.x != 0:
				axes["x"] = true
			if d.y != 0:
				axes["y"] = true
			if d.z != 0:
				axes["z"] = true
			prev = wp
		_check(
			axes.size() == 3,
			(
				"ascenseur %s : trajet complexe, %d segments sur %d axes"
				% [winding.cell, winding.path.size(), axes.size()]
			)
		)

	# Aller-retour, sur chacun des deux, avec le joueur à bord.
	for lift in lifts:
		lift.segment_duration = 0.0
		lift.rider_segment_duration = 0.0
		var start: Vector3i = lift.cell
		var target: Vector3i = lift.far_end()
		player.teleport_to(start)
		dm.notify_entered(start, player)
		await get_tree().process_frame
		_check(
			player.cell == target and lift.cell == target,
			"%s -> %s : la plateforme emmène son passager (%s)" % [start, target, player.cell]
		)
		dm.notify_entered(lift.cell, player)
		await get_tree().process_frame
		_check(
			player.cell == start and lift.cell == start,
			"y remonter le ramène à son point de départ (%s)" % player.cell
		)
