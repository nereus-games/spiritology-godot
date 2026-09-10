## Vérification headless de la rencontre : les capacités s'exécutent sans corrompre l'état
## de combat, la boucle est déterministe à seed égal, et chaque talent branche ses hooks.
## Sort en code 1 si l'un de ces points régresse.
##
## Lancé par : Godot --headless --path . res://scenes/dev/encounter_check.tscn
## (scène de démarrage, et non --script : voir geometry_check.gd.)
##
## Le manager ignore délibérément [GameSession] (cf. ses signaux `ifp_earned` /
## `object_consumed`, relayés par l'UI) : ce harnais tient donc le rôle que tient l'UI en
## jeu, et n'a besoin d'aucun autoload.
extends Node

const TalentCatalog := preload("res://scripts/encounter/talents/talent_catalog.gd")

const ABILITY_DIR := "res://data/abilities/"
const TALENT_IMPL_DIR := "res://scripts/encounter/talents/impl/"

## Seed de référence des rencontres rejouées. Toute valeur ferait l'affaire : ce qui
## compte est qu'elle soit FIXE, sinon le déterminisme ne se teste pas.
const SEED := 20260909

## Terrain de test : deux individus par camp, pour que les helpers de ciblage de
## l'[EncounterContext] (allies / opponents / others / first_opponent_in_order) aient
## tous de quoi répondre. Une capacité qui ne trouve pas de cible ne prouverait rien.
const PLAYER_SPECIES: Array[StringName] = [&"kalilk", &"fliritus"]
const RIVAL_SPECIES: Array[StringName] = [&"ravbak", &"skorpis"]

## Capacité quelconque, passée aux hooks de talents qui en attendent une.
const SAMPLE_ABILITY := &"anomaly"

var _fails: Array[String] = []
var _rng := RandomNumberGenerator.new()


## Agent qui joue des actions imposées, pour éprouver les chemins que l'[AutoAgent] ne
## prend jamais : il ne joue que des capacités et Meditate, donc Talk, Examine, Use Object,
## Steal et Flee ne seraient exercés par rien.
class ScriptedAgent:
	extends EncounterAgent

	var queued: Array = []

	func decide(_fighter: EncounterFighter, _manager: EncounterManager) -> EncounterAction:
		return queued.pop_front() if not queued.is_empty() else null


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
	_rng.seed = SEED
	_check_abilities()
	await _check_actions()
	await _check_determinism()
	await _check_loop_invariants()
	_check_talents()
	print("")
	if _fails.is_empty():
		print("TOUT OK")
	else:
		print("ÉCHECS : %s" % [_fails])
	get_tree().quit(0 if _fails.is_empty() else 1)


# --------------------------------------------------------------------------
# Terrain de test
# --------------------------------------------------------------------------


## Quatre combattants neufs : [j0, j1, r0, r1]. Reconstruits pour CHAQUE capacité, sinon
## une capacité qui dissout un camp priverait les suivantes de cibles.
func _fresh_fighters() -> Array:
	var out: Array = []
	for id in PLAYER_SPECIES:
		out.append(EncounterManager.make_fighter(id, true))
	for id in RIVAL_SPECIES:
		out.append(EncounterManager.make_fighter(id, false))
	return out


## Manager prêt à tourner. [EncounterManager] étant un Node jamais ajouté à l'arbre,
## l'appelant DOIT le `free()` — sinon Godot signale des instances fuitées en sortie.
func _make_manager(seed: int = SEED) -> EncounterManager:
	var fighters := _fresh_fighters()
	var m := EncounterManager.new()
	m.setup([fighters[0], fighters[1]], [fighters[2], fighters[3]], seed)
	return m


func _ability_files() -> Array:
	var out: Array = []
	var dir := DirAccess.open(ABILITY_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".tres"):
			out.append(ABILITY_DIR + f)
	out.sort()  # ordre stable : le journal du check reste comparable d'un run à l'autre
	return out


# --------------------------------------------------------------------------
# Capacités : chacune s'exécute et laisse l'état de combat cohérent
# --------------------------------------------------------------------------


func _check_abilities() -> void:
	print("— capacités —")
	var executed := 0
	var broken: Array[String] = []
	for path in _ability_files():
		var res := load(path)
		if not (res is AbilityData):
			continue  # les TalentData vivent dans le même dossier, cf. _check_talents
		var ability: AbilityData = res
		if ability.type != GameEnums.AbilityType.ENCOUNTER:
			continue  # les capacités d'exploration ont leur propre chemin d'exécution
		executed += 1
		var problem := _execute_ability(ability)
		if problem != "":
			broken.append("%s (%s)" % [ability.id, problem])
	_check(executed >= 100, "%d capacités de rencontre exécutées" % executed)
	_check(
		broken.is_empty(),
		(
			"état de combat sain après chaque capacité%s"
			% ("" if broken.is_empty() else " — " + ", ".join(broken))
		)
	)


## Exécute une capacité sur un terrain neuf. Renvoie "" si l'état reste cohérent,
## sinon la description du problème.
func _execute_ability(ability: AbilityData) -> String:
	var fighters := _fresh_fighters()
	var timeline := EncounterTimeline.new()
	timeline.setup(fighters)  # sans rng : ordre stable, donc positions et faiblesses connues
	var ctx := EncounterContext.new()
	ctx.ability = ability
	ctx.user = fighters[0]
	ctx.targets = [fighters[2]]
	ctx.all_fighters = fighters
	ctx.timeline = timeline
	ctx.rng = _rng
	# Une énergie concrète plutôt que NONE : c'est ce qui fait passer les capacités
	# Random/Variable par le vrai chemin (modificateurs, immunités) au lieu du court-circuit.
	ctx.resolved_energy = GameEnums.Energy.HEAT
	EffectCatalog.script_for(ability).execute(ctx)
	var problem := _state_problem(fighters, timeline)
	# Ces combattants ne passent pas par EncounterManager._finish() : c'est donc ici qu'il
	# faut casser leurs cycles de références, sinon les 108 terrains de test fuient.
	for f in fighters:
		f.release_cross_references()
	return problem


## Invariants que AUCUNE capacité ne doit pouvoir briser.
func _state_problem(fighters: Array, timeline: EncounterTimeline) -> String:
	for f in fighters:
		if f.den < 0 or f.den > f.max_den:
			return "DEN %d hors [0, %d] sur %s" % [f.den, f.max_den, f.species_id()]
		if f.eth < 0 or f.eth > f.max_eth:
			return "ETH %d hors [0, %d] sur %s" % [f.eth, f.max_eth, f.species_id()]
	# Les réordonnancements sont mis en attente et appliqués en fin de tour : les appliquer
	# ici est le seul moyen de voir l'ordre qu'une capacité a réellement demandé.
	timeline.apply_pending()
	if timeline.order.size() != fighters.size():
		return "ordre du tour à %d entrées au lieu de %d" % [timeline.order.size(), fighters.size()]
	for f in fighters:
		if not timeline.order.has(f):
			return "%s absent de l'ordre du tour" % f.species_id()
	return ""


# --------------------------------------------------------------------------
# Actions : chaque type de tour se résout et laisse l'état cohérent
# --------------------------------------------------------------------------


## Éprouve les huit [enum EncounterAction.Kind] via la boucle PUBLIQUE — un agent scripté
## impose l'action, `run()` la résout. Passer par `_resolve_action()` directement testerait
## le résolveur sans son contexte ; ici on teste ce que le jeu exécute vraiment.
func _check_actions() -> void:
	print("— actions —")
	var untested: Array[String] = []
	var broken: Array[String] = []
	for kind in EncounterAction.Kind.values():
		var m := _make_manager()
		var actor: EncounterFighter = m.players[0]
		var target: EncounterFighter = m.rivals[0]
		# Le manager ignore les autoloads : c'est l'UI qui lui résout les objets en jeu.
		m.object_provider = func(id): return load("res://data/objects/%s.tres" % id)
		var agent := ScriptedAgent.new()
		agent.queued = [_action_of_kind(kind, actor, target, m)]
		m.set_agent(actor, agent)
		# On écoute le tour de CET acteur : `run(1)` fait aussi jouer les autres, donc la
		# taille du journal grossirait même si l'action imposée ne produisait rien.
		var spoke := [false]
		m.turn_taken.connect(
			func(f, _a, lines):
				if f == actor and not lines.is_empty():
					spoke[0] = true
		)
		await m.run(1)
		if not spoke[0]:
			untested.append(EncounterAction.Kind.keys()[kind])
		var problem := _state_problem(m.players + m.rivals, m.timeline)
		if problem != "":
			broken.append("%s (%s)" % [EncounterAction.Kind.keys()[kind], problem])
		m.free()
	_check(
		untested.is_empty(),
		(
			"chaque type d'action produit une ligne de journal%s"
			% ("" if untested.is_empty() else " — muets : " + ", ".join(untested))
		)
	)
	_check_empty(broken, "état de combat sain après chaque type d'action")


func _action_of_kind(
	kind: int, actor: EncounterFighter, target: EncounterFighter, m: EncounterManager
) -> EncounterAction:
	match kind:
		EncounterAction.Kind.ABILITY:
			var usable := m.usable_abilities(actor)
			var ability: AbilityData = usable[0] if not usable.is_empty() else null
			return EncounterAction.use_ability(ability, [target])
		EncounterAction.Kind.USE_OBJECT:
			var a := EncounterAction.of_kind(EncounterAction.Kind.USE_OBJECT, [target])
			a.object_id = &"rune_stone"
			return a
		EncounterAction.Kind.MEDITATE, EncounterAction.Kind.PASS:
			return EncounterAction.of_kind(kind, [actor])
		_:
			return EncounterAction.of_kind(kind, [target])


## Échec listant les fautifs (même forme que les autres checks du projet).
func _check_empty(offenders: Array, label: String) -> void:
	if offenders.is_empty():
		_check(true, label)
		return
	_check(false, "%s — %s" % [label, ", ".join(offenders)])


# --------------------------------------------------------------------------
# Déterminisme : c'est lui qui rendra tout refactor de la boucle vérifiable
# --------------------------------------------------------------------------


func _check_determinism() -> void:
	print("— déterminisme —")
	var a := await _run_once(SEED)
	var b := await _run_once(SEED)
	_check(a["result"] == b["result"], "même seed → même issue (%s)" % a["result"])
	_check(a["rounds"] == b["rounds"], "même seed → même nombre de rondes (%d)" % a["rounds"])
	_check(a["log"] == b["log"], "même seed → même journal (%d lignes)" % a["log"].size())
	# Contrôle négatif : sans lui, les assertions ci-dessus passeraient tout aussi bien
	# sur une rencontre où le rng ne piloterait plus rien. On compare des ordres du tour
	# initiaux (24 permutations pour 4 combattants) plutôt que deux journaux, qui
	# pourraient coïncider par hasard sur un combat court.
	var orders := {}
	for i in 10:
		var m := _make_manager(SEED + i)
		orders[",".join(m.timeline.order.map(func(f): return String(f.species_id())))] = true
		m.free()
	_check(
		orders.size() > 1,
		"seeds différents → ordres du tour différents (%d distincts sur 10)" % orders.size()
	)


func _run_once(seed: int) -> Dictionary:
	var m := _make_manager(seed)
	var res := await m.run()
	var out := {"result": res, "log": m.battle_log, "rounds": m.round_number}
	m.free()
	return out


# --------------------------------------------------------------------------
# Boucle : positions, faiblesses, terminaison
# --------------------------------------------------------------------------


func _check_loop_invariants() -> void:
	print("— boucle —")
	var m := _make_manager()
	var order := m.timeline.order
	_check(order.size() == 4, "ordre du tour : %d combattants" % order.size())
	_check(
		m.timeline.position_of(order[0]) == GameEnums.TurnPosition.FIRST,
		"tête de l'ordre → position FIRST"
	)
	_check(
		m.timeline.position_of(order[1]) == GameEnums.TurnPosition.MIDDLE,
		"milieu de l'ordre → position MIDDLE"
	)
	_check(
		m.timeline.position_of(order[3]) == GameEnums.TurnPosition.LAST,
		"queue de l'ordre → position LAST"
	)
	# La faiblesse active est dérivée de la POSITION, pas de l'individu : c'est la règle
	# qui rend les capacités de réordonnancement offensives.
	var head: EncounterFighter = order[0]
	_check(
		(
			head.active_weakness(GameEnums.TurnPosition.FIRST) == head.species.weakness_first
			and head.active_weakness(GameEnums.TurnPosition.LAST) == head.species.weakness_last
		),
		"faiblesse active dérivée de la position"
	)
	m.free()

	# Terminaison : la boucle rend toujours une des trois issues et respecte max_rounds.
	var m2 := _make_manager()
	var res := await m2.run(3)
	_check(res in [&"victory", &"defeat", &"timeout"], "issue valide : %s" % res)
	_check(
		m2.round_number >= 1 and m2.round_number <= 3,
		"rondes bornées par max_rounds (%d)" % m2.round_number
	)
	_check(m2.result == res, "le champ result reflète l'issue rendue")
	_check(
		not m2.battle_log.is_empty(),
		"la rencontre a produit un journal (%d lignes)" % m2.battle_log.size()
	)
	m2.free()


# --------------------------------------------------------------------------
# Talents : chacun résout vers son script dédié et répond à tous les hooks
# --------------------------------------------------------------------------


func _check_talents() -> void:
	print("— talents —")
	var m := _make_manager()
	var owner: EncounterFighter = m.players[0]
	var other: EncounterFighter = m.rivals[0]
	var sample := m.resolve_ability(SAMPLE_ABILITY)
	var resolved := 0
	var problems: Array[String] = []
	for path in _ability_files():
		var res := load(path)
		if not (res is TalentData):
			continue
		var td: TalentData = res
		var impl := TALENT_IMPL_DIR + String(td.id) + ".gd"
		if not ResourceLoader.exists(impl):
			problems.append("%s sans script dédié" % td.id)
			continue
		var script = TalentCatalog.script_for(td, owner, 1)
		if script.get_script().resource_path != impl:
			problems.append("%s non résolu vers son script" % td.id)
			continue
		resolved += 1
		# Tous les hooks, dans l'ordre où la boucle les appelle. Les talents encore stubs
		# doivent rester no-op : ne rien faire est une réponse valide, échouer ne l'est pas.
		script.on_encounter_start(m)
		script.modify_talk_chance(m, owner, other, 0.3)
		script.on_talk_resolved(m, owner, other, true)
		script.allows_ally_talk(m)
		script.wants_reuse(m, owner, sample)
		script.on_weakness_touched(m, owner, other, sample)
		script.modify_examine_info(m, other, 1.0)
		var kinds: Array = [
			EncounterAction.Kind.ABILITY, EncounterAction.Kind.TALK, EncounterAction.Kind.EXAMINE
		]
		script.modify_menu(m, kinds)
		if kinds.is_empty():
			problems.append("%s vide le menu d'actions" % td.id)
		script.on_encounter_end(m, &"victory")
	_check(resolved == 10, "%d talents résolus vers leur script dédié" % resolved)
	_check(
		problems.is_empty(),
		"hooks de talents opérants%s" % ("" if problems.is_empty() else " — " + ", ".join(problems))
	)
	m.free()
