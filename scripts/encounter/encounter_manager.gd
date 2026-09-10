## Orchestrateur d'une rencontre : ordre du tour, résolution des actions, fin de combat.
##
## Branche le système d'effets ([EffectCatalog]) sur l'état de combat ([EncounterFighter],
## [EncounterTimeline]). L'ordre du tour est fixé au départ et modifiable par les
## capacités ; la position détermine la faiblesse active. Modèle par RONDE : à chaque
## ronde, tout le monde agit une fois (état de tour réinitialisé en début, réordonnancement
## appliqué en fin).
##
## Le manager ne DÉCIDE pas : il demande son action à chaque tour au [EncounterAgent] du
## combattant ([method set_agent]). Par défaut tous les combattants sont en [AutoAgent] et
## [method run] résout la rencontre d'une traite, sans suspension — c'est le mode auto
## testable headless. Poser un [UiAgent] sur un combattant suffit à rendre ses tours
## pilotables : la boucle, elle, ne change pas.
class_name EncounterManager
extends Node

## `action` est l'[EncounterAction] jouée ; `lines` le journal produit par ses effets.
signal turn_taken(fighter: EncounterFighter, action: EncounterAction, lines: PackedStringArray)
signal ended(result: StringName)  ## &"victory" / &"defeat" / &"timeout"

## IFP d'encyclopédie gagnés par une action du joueur sur un rival (Examine / Talk /
## dissolution). Le manager ne connaît PAS [GameSession] — il resterait sinon intestable
## en `--script`, qui ne charge pas les autoloads : c'est l'UI de rencontre qui branche ce
## signal sur [method GameSession.award_ifp], comme elle le fait déjà pour le DEN/ETH.
signal ifp_earned(
	species_id: StringName, action: GameEnums.IfpAction, is_forlorn: bool, dialogue_effective: bool
)

## Objet consommé par une action Use / Give (« Objects are all consumable items »). L'UI
## le retire de l'inventaire [GameSession] — même raison que [signal ifp_earned].
signal object_consumed(object_id: StringName)

## Résout un slug d'objet en [ObjectData]. Injecté par l'UI (`GameData.object`) : le
## manager ne connaît pas les autoloads, sinon il ne serait plus testable en `--script`.
var object_provider: Callable = Callable()

const ABILITY_DIR := "res://data/abilities/"

## Résolveur des scripts de talents (passifs d'espèce). Chargé par preload : ni
## [TalentCatalog] ni [TalentScript] n'ont de `class_name` (scripts neufs, absents du
## cache de classes globales que seul l'éditeur régénère — le jeu se lance en CLI).
const TalentCatalog := preload("res://scripts/encounter/talents/talent_catalog.gd")

var players: Array = []
var rivals: Array = []
var timeline: EncounterTimeline
var rng := RandomNumberGenerator.new()
## Espèces à 100 % d'encyclopédie (modificateur de dégâts). species_id -> true.
var completed_species: Dictionary = {}

## Résultat de la rencontre une fois [method run] terminé (&"" tant qu'elle court).
## [method run] étant une coroutine, sa valeur de retour n'est lisible qu'avec `await` :
## les appelants qui ne peuvent pas attendre lisent ce champ ou le signal [signal ended].
var result := &""

## Ronde en cours, 1-based (0 tant que la rencontre n'a pas démarré). Lu par l'UI.
var round_number := 0

var battle_log: PackedStringArray = PackedStringArray()

## Fournisseur d'action par combattant (EncounterFighter -> EncounterAgent). Les
## combattants absents utilisent [member default_agent].
var _agents: Dictionary = {}
var default_agent: EncounterAgent = AutoAgent.new()

## Talents actifs de la rencontre : un [TalentScript] par combattant PORTEUR (les autres
## n'en ont pas). Peuplé par [method _collect_talents] dans [method setup]. Le manager
## appelle leurs hooks aux points clés de la boucle (début/fin, Talk, capacité consommée…).
var _talents: Array = []

var _round_energy := GameEnums.Energy.NONE


## Prépare la rencontre. `player_fighters` / `rival_fighters` = [EncounterFighter].
## Réinitialise les agents : poser les [UiAgent] APRÈS cet appel.
func setup(
	player_fighters: Array, rival_fighters: Array, seed: int = 0, completed: Dictionary = {}
) -> void:
	players = player_fighters
	rivals = rival_fighters
	completed_species = completed
	rng.seed = seed
	result = &""
	_agents.clear()
	timeline = EncounterTimeline.new()
	# « Turn order is defined at random when the encounter begins » (doc, Encounters). Ce
	# n'est pas cosmétique : la position dans l'ordre fixe la faiblesse active de chacun,
	# donc un ordre figé figerait aussi les faiblesses. Tiré par le rng seedé ci-dessus →
	# aléatoire d'une rencontre à l'autre, mais reproductible à seed égal.
	timeline.setup(players + rivals, rng)
	_collect_talents()


## Instancie un [TalentScript] par combattant qui porte un talent (via [member
## SpeciesData.talent]). Le cumul en duo (deux individus de même espèce dans une équipe)
## est porté par le champ `stacks` — compté sur le camp du porteur, borné à 1 si le talent
## n'est pas cumulable ([member TalentData.stacks_in_duo]).
func _collect_talents() -> void:
	_talents.clear()
	for f in players + rivals:
		if f.species == null or f.species.talent == &"":
			continue
		var td := _load_talent(f.species.talent)
		if td == null:
			continue
		var stacks := 1
		if td.stacks_in_duo:
			stacks = allies_of(f).filter(func(a): return a.species_id() == f.species_id()).size()
		_talents.append(TalentCatalog.script_for(td, f, stacks))


## Charge un [TalentData] par slug. Les talents sont générés dans le MÊME dossier que les
## capacités (`data/abilities/`) mais sont d'un type distinct : le `as TalentData` renvoie
## null pour un slug qui serait une capacité, ce qui est le comportement voulu.
func _load_talent(slug: StringName) -> TalentData:
	if slug == &"":
		return null
	var path := ABILITY_DIR + String(slug) + ".tres"
	return load(path) as TalentData if ResourceLoader.exists(path) else null


## Ligne de journal produite par un talent (pas rattachée à un tour précis). Préfixée pour
## se distinguer des lignes d'action dans le log de combat.
func note_talent(line: String) -> void:
	battle_log.append("⁘ %s" % line)


## Construit un combattant à partir d'un slug d'espèce (charge le SpeciesData).
static func make_fighter(species_id: StringName, is_player: bool) -> EncounterFighter:
	var sp: SpeciesData = load("res://data/species/%s.tres" % species_id)
	if sp == null:
		push_error("[EncounterManager] espèce introuvable : %s" % species_id)
		return null
	return EncounterFighter.new(sp, is_player)


# --- Agents ---


## Assigne un fournisseur d'action à un combattant (sinon [member default_agent]).
func set_agent(fighter: EncounterFighter, agent: EncounterAgent) -> void:
	_agents[fighter] = agent


func agent_for(fighter: EncounterFighter) -> EncounterAgent:
	return _agents.get(fighter, default_agent)


# --- Options offertes aux agents ---


## Capacités de RENCONTRE encore au répertoire de `fighter` (usage unique consommé exclu),
## Y COMPRIS celles qu'il ne peut pas payer — le menu joueur les affiche grisées plutôt
## que de les masquer. Cf. [method usable_abilities] pour les seules jouables.
func encounter_abilities(fighter: EncounterFighter) -> Array:
	var out: Array = []
	for aid in fighter.ability_ids:
		var a := resolve_ability(aid)
		if a != null and a.type == GameEnums.AbilityType.ENCOUNTER and not fighter.is_spent(a):
			out.append(a)
	return out


## Capacités que `fighter` peut jouer maintenant (payables et non consommées). Source de
## la politique auto ; le menu joueur s'en sert pour détecter le tour perdu.
func usable_abilities(fighter: EncounterFighter) -> Array:
	return encounter_abilities(fighter).filter(func(a): return fighter.can_use(a))


## Vrai si la capacité vise les adversaires. Heuristique d'ÉCHAFAUDAGE sur les tags, en
## attendant que Notion décrive le ciblage capacité par capacité (les tags ne sont qu'une
## catégorisation, cf. [EffectCatalog]).
func is_offensive(ability: AbilityData) -> bool:
	return (
		ability.tags.has("damage")
		or ability.tags.has("ETH loss")
		or ability.tags.has("change weakness")
		or ability.tags.has("limit actions")
	)


## Cibles possibles pour `fighter` jouant `ability` : les adversaires en lice si la
## capacité est offensive, sinon lui-même. Règle unique partagée par la politique auto
## ([AutoAgent]) et le ciblage du menu joueur — une seule candidate = aucun choix à faire.
## Les capacités à portée globale (Tumult…) élargissent elles-mêmes leur portée à
## l'exécution via [member EncounterContext.all_fighters] : ce ciblage ne les concerne pas.
func candidate_targets(fighter: EncounterFighter, ability: AbilityData) -> Array:
	if is_offensive(ability):
		return opponents_of(fighter).filter(func(f): return not f.is_dissolved())
	return [fighter]


func opponents_of(fighter: EncounterFighter) -> Array:
	return rivals if fighter.is_player else players


## Adversaires encore en lice : cibles de Talk / Examine / Give Object.
func living_opponents(fighter: EncounterFighter) -> Array:
	return opponents_of(fighter).filter(func(f): return not f.is_dissolved())


## Actions « de base » (hors Meditate/Object, qui ont leur logique propre) offertes à un
## fighter, APRÈS mutation par ses talents. Départ = ABILITY, TALK, EXAMINE ; un talent
## peut retirer ABILITY/TALK et ajouter FLEE (Run Away) ou STEAL — run_away_2, steal,
## slick_merchant l'expriment via [method TalentScript.modify_menu]. Le menu joueur et
## l'IA consultent cette liste pour savoir quoi proposer. L'ordre initial est conservé ;
## les ajouts arrivent en fin.
func menu_kinds(fighter: EncounterFighter) -> Array:
	var kinds: Array = [
		EncounterAction.Kind.ABILITY, EncounterAction.Kind.TALK, EncounterAction.Kind.EXAMINE
	]
	for t in _talents:
		if t.owner == fighter:
			t.modify_menu(self, kinds)
	return kinds


## Cibles possibles d'un Talk du fighter : les rivaux vivants, plus ses alliés vivants si un
## talent l'autorise (Serene Waves : parler à l'équipier le soigne). Le porteur est exclu.
func talk_targets(fighter: EncounterFighter) -> Array:
	var targets := living_opponents(fighter)
	for t in _talents:
		if t.owner == fighter and t.allows_ally_talk(self):
			for a in allies_of(fighter):
				if a != fighter and not a.is_dissolved() and not targets.has(a):
					targets.append(a)
			break
	return targets


func allies_of(fighter: EncounterFighter) -> Array:
	return players if fighter.is_player else rivals


func resolve_ability(aid: StringName) -> AbilityData:
	var path := ABILITY_DIR + String(aid) + ".tres"
	return load(path) as AbilityData if ResourceLoader.exists(path) else null


# --- Boucle ---


## Lance la boucle SANS attendre sa fin, pour les appelants qui réagissent au signal
## [signal ended] / au champ [member result] plutôt qu'au retour (l'UI de rencontre, qui
## rend la main à sa scène). [method run] étant une coroutine, GDScript refuse de
## l'appeler sans `await` : l'appel dynamique ci-dessous est ce détour, assumé et isolé
## ici. Utiliser `await run()` directement quand on peut attendre le résultat.
func start(max_rounds: int = 30) -> void:
	run.call(max_rounds)


## Déroule la rencontre jusqu'à sa fin et renvoie le résultat. Coroutine : suspend sur
## les tours pilotés par un [UiAgent], ne suspend jamais si tous les agents sont autos.
func run(max_rounds: int = 30) -> StringName:
	for t in _talents:
		t.on_encounter_start(self)
	for _r in max_rounds:
		_begin_round()
		for fighter in timeline.order.duplicate():
			if fighter.is_dissolved():
				continue
			await _take_turn(fighter)
			var res := _check_end()
			if res != &"":
				return _finish(res)
		timeline.apply_pending()
	return _finish(&"timeout")


func _finish(res: StringName) -> StringName:
	result = res
	# Talents de fin de rencontre (Restore : soin du duo ; Trick to Reveal : révélation carte)
	# AVANT d'émettre `ended` : l'UI resynchronise DEN/ETH vers GameSession sur ce signal, et
	# doit donc voir l'état déjà soigné.
	for t in _talents:
		t.on_encounter_end(self, res)
	ended.emit(res)
	# APRÈS le signal : les écouteurs voient l'état complet, puis on casse les cycles de
	# références entre combattants (cf. EncounterFighter.release_cross_references).
	for f in players + rivals:
		f.release_cross_references()
	return res


func _begin_round() -> void:
	# Numéro de ronde, 1-based. Exposé pour l'UI : la doc veut le numéro du tour courant
	# affiché en permanence dans le LOG, indépendamment du défilement.
	round_number += 1
	# Énergie aléatoire commune à la ronde (capacités Random/Variable).
	_round_energy = _random_energy()
	for f in timeline.order:
		f.clear_turn_state()


func _take_turn(fighter: EncounterFighter) -> void:
	# L'agent peut être synchrone (auto) ou coroutine (UI) : `await` couvre les deux.
	@warning_ignore("redundant_await")
	var action: EncounterAction = await agent_for(fighter).decide(fighter, self)
	if action == null:
		battle_log.append("%s n'a aucune action possible." % fighter.display_name())
		return
	var dissolved_before := rivals.filter(func(f): return f.is_dissolved())
	_resolve_action(fighter, action)
	if fighter.is_player:
		_award_dissolutions(dissolved_before)


## « Use Ability – upon dissolving rival » : les rivaux que CE tour du joueur vient de
## dissoudre octroient leurs IFP. Un rival abattu par un autre rival (réflexion,
## redirection) n'en octroie pas — d'où le garde `fighter.is_player` côté appelant.
func _award_dissolutions(dissolved_before: Array) -> void:
	for r in rivals:
		if r.is_dissolved() and not dissolved_before.has(r):
			ifp_earned.emit(
				r.species_id(), GameEnums.IfpAction.DISSOLVE_RIVAL, _is_forlorn(r), true
			)


func _resolve_action(fighter: EncounterFighter, action: EncounterAction) -> void:
	match action.kind:
		EncounterAction.Kind.ABILITY:
			_resolve_ability(fighter, action)
		EncounterAction.Kind.MEDITATE:
			_resolve_meditate(fighter, action)
		EncounterAction.Kind.TALK:
			_resolve_talk(fighter, action)
		EncounterAction.Kind.EXAMINE:
			_resolve_examine(fighter, action)
		EncounterAction.Kind.USE_OBJECT:
			_resolve_object(fighter, action)
		EncounterAction.Kind.STEAL:
			_resolve_steal(fighter, action)
		EncounterAction.Kind.FLEE:
			_resolve_flee(fighter, action)
		EncounterAction.Kind.PASS:
			# Action « … » : passe le tour SANS changer l'ordre (doc UI).
			_emit_turn(fighter, action, ["passe son tour."])
		_:
			_emit_turn(fighter, action, ["action « %s » pas encore résolue." % action.label()])


## Use / Give Object : « select object and target (can be a rival) ; "Use" if target is
## player character, "Give" if target is rival ». L'objet est CONSOMMÉ dans tous les cas
## (« Objects are all consumable items »), y compris quand l'effet ne fait rien en
## rencontre — le donner à un rival est en soi le geste utile (dialogues).
##
## Le retrait de l'inventaire n'est PAS fait ici : le manager ne connaît pas [GameSession]
## (cf. [signal ifp_earned]). Il émet [signal object_consumed], que l'UI relaie.
func _resolve_object(fighter: EncounterFighter, action: EncounterAction) -> void:
	var obj: ObjectData = (
		object_provider.call(action.object_id) if object_provider.is_valid() else null
	)
	if obj == null:
		_emit_turn(fighter, action, ["objet introuvable : %s." % action.object_id])
		return
	var target := _first_target(action)
	if target == null:
		target = fighter
	var given := not target.is_player
	object_consumed.emit(action.object_id)
	var lines: Array = []
	match obj.effect:
		GameEnums.ObjectEffect.HEAL_DEN:
			# « gives Y DEN to a target » — Y est un placeholder surligné dans Notion, donc
			# magnitude vaut 0 tant qu'il n'est pas chiffré : on retombe sur l'équilibrage.
			var amount: int = (
				obj.magnitude if obj.magnitude > 0 else BalanceData.current().object_heal_den
			)
			var before := target.den
			target.recover_den(amount)
			lines.append(
				(
					"%s %s à %s : DEN %d -> %d."
					% [
						"donne" if given else "utilise",
						tr(obj.name_key()),
						target.display_name(),
						before,
						target.den
					]
				)
			)
		GameEnums.ObjectEffect.FLEE_ENCOUNTER:
			# « allows to Run away from an encounter ». La fuite elle-même (téléportation à
			# 3-5 cases, 50 % de chance que le rival disparaisse) appartient à l'exploration,
			# qui ne la gère pas encore — d'où le stub partagé avec la capacité de fuite.
			lines.append(
				(
					"%s %s : fuite (TODO exploration)."
					% ["donne" if given else "utilise", tr(obj.name_key())]
				)
			)
		_:
			# NONE (Notice), CURE_POISON, DISGUISE, DIG, AVOID_PURSUIT : sans effet EN
			# RENCONTRE. Notice est explicitement « no effect » et sert à être donné ; les
			# autres relèvent de l'exploration (sols friables, poison, poursuite).
			lines.append(
				(
					"%s %s à %s."
					% ["donne" if given else "utilise", tr(obj.name_key()), target.display_name()]
				)
			)
	_emit_turn(fighter, action, lines)


## Steal (talent granop) : « takes an object from the target, but has a risk of a member of
## The Coal Vetch appearing ; if present, Steal has a 50 % chance of failing ».
## STUB : voler un objet suppose que les rivaux en PORTENT (pas de telle donnée dans Notion),
## et l'apparition du Coal Vetch est un système inexistant (comme le déclencheur d'Examine).
## L'action est routée et journalisée pour que la chaîne menu→résolution soit complète le
## jour où ces systèmes existeront.
func _resolve_steal(fighter: EncounterFighter, action: EncounterAction) -> void:
	var target := _first_target(action)
	if target == null:
		_emit_turn(fighter, action, ["n'a personne à voler."])
		return
	_emit_turn(
		fighter,
		action,
		["tente de voler %s [objet volé / Coal Vetch à venir]." % target.display_name()]
	)


## Run Away (action de menu donnée par un talent : run_away_2, slick_merchant). Quitter
## réellement la rencontre suppose la téléportation en exploration (3-5 cases, 50 % que le
## rival disparaisse), non bâtie — d'où le stub, partagé d'intention avec EncounterContext.flee.
## slick_merchant coûte 10 ETH et un QTE (faillible) ; run_away_2 est gratuit et sûr — ces
## conditions seront portées par le talent quand la fuite aboutira réellement.
func _resolve_flee(fighter: EncounterFighter, action: EncounterAction) -> void:
	_emit_turn(fighter, action, ["tente de fuir la rencontre [téléportation exploration à venir]."])


## Meditate : « character recovers X ETH; damage +Y % until next turn ». Le +Y % porte sur
## les dégâts INFLIGÉS (décision de design) et s'applique au PROCHAIN tour du méditant, seul
## moment où il peut frapper — cf. EncounterFighter.grant_next_turn_damage_bonus.
func _resolve_meditate(fighter: EncounterFighter, action: EncounterAction) -> void:
	var before := fighter.eth
	var balance := BalanceData.current()
	fighter.recover_eth(balance.meditate_eth)
	fighter.grant_next_turn_damage_bonus(balance.meditate_damage_bonus)
	_emit_turn(
		fighter,
		action,
		[
			(
				"médite : ETH %d -> %d, dégâts +%d %% au prochain tour."
				% [before, fighter.eth, roundi(balance.meditate_damage_bonus * 100.0)]
			)
		]
	)


## Talk : « initiate dialogue with rival ». N'octroie des IFP que si le dialogue est
## effectif (restriction 2 de GameSession.award_ifp).
func _resolve_talk(fighter: EncounterFighter, action: EncounterAction) -> void:
	var target := _first_target(action)
	if target == null:
		_emit_turn(fighter, action, ["parle dans le vide."])
		return
	# Effectivité du dialogue : PLACEHOLDER assumé. La doc conditionne les IFP de Talk à un
	# dialogue « effectif » sans jamais en donner la règle, et ses brouillons de dialogues la
	# font dépendre d'objets donnés au rival — système inexistant. On se rabat sur le
	# talker_chance de l'espèce, qui décrit en réalité la propension du RIVAL à engager le
	# dialogue : proxy, pas la règle. À remplacer quand le système de dialogue existera.
	var chance: float = target.species.talker_chance if target.species else 0.0
	# Les talents du camp du parleur peuvent ajuster l'effectivité (Slick Merchant : +15 %
	# sur les 3 premiers tours — sur ce proxy `talker_chance`, faute de système de dialogue).
	var speaker_team := allies_of(fighter)
	for t in _talents:
		if speaker_team.has(t.owner):
			chance = t.modify_talk_chance(self, fighter, target, chance)
	var effective := rng.randf() < chance
	ifp_earned.emit(
		target.species_id(), GameEnums.IfpAction.TALK_RIVAL, _is_forlorn(target), effective
	)
	_emit_turn(
		fighter,
		action,
		[
			(
				"parle à %s : dialogue %s."
				% [target.display_name(), "effectif" if effective else "sans effet"]
			)
		]
	)
	# Réactions de talents au Talk résolu (Serene Waves : soin de l'équipier ; Slick
	# Merchant : la faiblesse du rival prend celle du parleur).
	for t in _talents:
		if speaker_team.has(t.owner):
			t.on_talk_resolved(self, fighter, target, effective)


## Examine : « gets info on rival; reveals objects they carry; rival may react with Talk or
## Challenge ». La révélation d'objets et la réaction du rival dépendent de systèmes non
## bâtis ; les IFP, eux, sont octroyés (Examine « works all the time »).
func _resolve_examine(fighter: EncounterFighter, action: EncounterAction) -> void:
	var target := _first_target(action)
	if target == null:
		_emit_turn(fighter, action, ["n'a personne à examiner."])
		return
	ifp_earned.emit(
		target.species_id(), GameEnums.IfpAction.EXAMINE_RIVAL, _is_forlorn(target), true
	)
	# Recon Glide (ravbak) : le gain d'info d'Examine du porteur est majoré (+10 %). La
	# magnitude de base d'un Examine n'est pas chiffrée (système d'info non bâti) : on part
	# de 1.0 et on journalise le facteur obtenu — observable, mais sans effet tant que le
	# gain d'info n'existe pas.
	var info := 1.0
	for t in _talents:
		if t.owner == fighter:
			info = t.modify_examine_info(self, target, info)
	# TODO: « reveals objects they carry » — les rivaux ne portent pas d'objets (pas de
	# base d'objets Notion), et la réaction Talk/Challenge du rival examiné reste à faire.
	# TODO: Coal Vetch — 2 Examine sur le même rival (ou 1 capacité) déclenchent X % de
	# chance qu'un agent apparaisse dans la rencontre. Système inexistant.
	var suffix := " (info ×%.2f)" % info if not is_equal_approx(info, 1.0) else ""
	_emit_turn(fighter, action, ["examine %s%s." % [target.display_name(), suffix]])


## Vrai si ce combattant est la variante Forlorn de son espèce.
## TODO: les variantes Forlorn ne sont pas modélisées sur EncounterFighter (SpeciesData ne
## porte qu'une capacité et un sprite Forlorn). Tant que c'est le cas, les IFP majorés
## Forlorn ne peuvent pas tomber — cf. restriction 3 de GameSession.award_ifp.
func _is_forlorn(_fighter: EncounterFighter) -> bool:
	return false


func _first_target(action: EncounterAction) -> EncounterFighter:
	for t in action.targets:
		if t is EncounterFighter and not t.is_dissolved():
			return t
	return null


func _emit_turn(fighter: EncounterFighter, action: EncounterAction, lines: Array) -> void:
	var packed := PackedStringArray(lines)
	for l in packed:
		battle_log.append("%s · %s" % [fighter.display_name(), l])
	turn_taken.emit(fighter, action, packed)


func _resolve_ability(fighter: EncounterFighter, action: EncounterAction) -> void:
	if action.ability == null:
		_emit_turn(fighter, action, ["capacité introuvable."])
		return
	var ability := action.ability
	# Cibles dont la faiblesse ACTIVE est touchée par l'énergie de la capacité — capturé
	# AVANT l'effet (l'effet peut changer les faiblesses en cours de route). Sert au talent
	# Examine Weakness. Détection best-effort, cf. [method _weakness_touched_targets].
	var touched := _weakness_touched_targets(fighter, ability, action.targets)
	# Coût payé AVANT l'effet : une capacité qui rend de l'ETH ne doit pas se rembourser.
	# Les agents ne proposent que du payable ([method usable_abilities]) ; en cas de
	# dépassement, pay_eth borne à 0 plutôt que de laisser filer l'ETH en négatif.
	fighter.pay_eth(ability.eth_cost())
	var ctx := EncounterContext.new()
	ctx.ability = ability
	ctx.user = fighter
	ctx.targets = action.targets
	ctx.all_fighters = timeline.living()
	ctx.timeline = timeline
	ctx.rng = rng
	ctx.completed_species = completed_species
	ctx.resolved_energy = _round_energy
	EffectCatalog.script_for(ability).execute(ctx)
	fighter.mark_used(ability)
	# Reuse (jézal) : une capacité à usage unique peut redevenir disponible.
	if ability.single_use:
		for t in _talents:
			if t.owner == fighter and t.wants_reuse(self, fighter, ability):
				fighter.clear_used(ability)
				note_talent(
					"%s : %s redevient disponible (Reuse)." % [fighter.display_name(), ability.id]
				)
				break
	# Examine Weakness (gélmi) : info glanée quand une faiblesse est touchée (attaquant OU cible).
	for target in touched:
		for t in _talents:
			t.on_weakness_touched(self, fighter, target, ability)
	for l in ctx.log_lines:
		battle_log.append("%s · %s : %s" % [fighter.display_name(), ability.id, l])
	turn_taken.emit(fighter, action, ctx.log_lines)


## Cibles dont la faiblesse active correspond à l'énergie effective de la capacité.
## Best-effort : l'énergie Random/Variable est résolue via [member _round_energy] (comme le
## fait [EncounterContext]), mais les overrides d'énergie internes à un effet ne sont pas vus.
## Suffisant pour Examine Weakness, dont l'effet (gain d'info) est de toute façon un stub.
func _weakness_touched_targets(
	_user: EncounterFighter, ability: AbilityData, targets: Array
) -> Array:
	var energy := ability.energy if ability else GameEnums.Energy.NONE
	if energy == GameEnums.Energy.RANDOM or energy == GameEnums.Energy.VARIABLE:
		energy = _round_energy
	if energy == GameEnums.Energy.NONE:
		return []
	var out: Array = []
	for target in targets:
		if target is EncounterFighter and not target.is_dissolved():
			if energy == target.active_weakness(timeline.position_of(target)):
				out.append(target)
	return out


func _check_end() -> StringName:
	if rivals.all(func(f): return f.is_dissolved()):
		return &"victory"
	if players.all(func(f): return f.is_dissolved()):
		return &"defeat"
	return &""


func _random_energy() -> GameEnums.Energy:
	var pool := [
		GameEnums.Energy.HEAT,
		GameEnums.Energy.FLUID,
		GameEnums.Energy.CRYSTAL,
		GameEnums.Energy.ARCANE,
		GameEnums.Energy.TOXIC
	]
	return pool[rng.randi_range(0, pool.size() - 1)]
