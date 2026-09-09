## UI de rencontre (overlay 2D au-dessus de l'exploration).
##
## Le duo du joueur est piloté par un [UiAgent] : à chaque tour d'un de ses membres, la
## boucle du [EncounterManager] se suspend, le menu s'ouvre (capacité puis cible), et le
## choix validé la relance. Les rivaux restent sur l'agent auto par défaut. Émet [signal
## finished] quand le joueur ferme l'overlay ; le [TransitionManager] nettoie alors et
## relance l'exploration.
##
## Mise en page : celle du mockup Notion (User Interface / Encounters).
## - haut gauche : boutons LOG et MENU ;
## - haut centre : la timeline (ordre du tour), une case par combattant ;
## - centre : les pleines planches des rivaux ;
## - bas : la barre d'actions horizontale, qui cède la place à une liste verticale pour
##   les sous-choix (capacité, objet, cible).
##
## Le LOG n'est plus affiché en permanence : c'est un panneau que l'on ouvre, comme dans
## le mockup, avec le numéro de ronde épinglé hors défilement.
extends CanvasLayer

signal finished(result: StringName)

## Chargé par preload et non par `class_name` : voir l'en-tête du script visé.
const TimelineEntry := preload("res://scripts/ui/encounter_timeline_entry.gd")

## Icônes d'ÉNERGIE des capacités (menu). On réutilise l'ANCIEN jeu (`ui/weaknesses/`) —
## la timeline, elle, a désormais son propre jeu d'icônes de faiblesse. RANDOM/VARIABLE/NONE
## n'ont pas d'icône ; le libellé de la capacité les signale alors en toutes lettres.
const ENERGY_ICONS := {
	GameEnums.Energy.HEAT: "res://assets/sprites/ui/weaknesses/heat.png",
	GameEnums.Energy.FLUID: "res://assets/sprites/ui/weaknesses/fluid.png",
	GameEnums.Energy.CRYSTAL: "res://assets/sprites/ui/weaknesses/crystal.png",
	GameEnums.Energy.ARCANE: "res://assets/sprites/ui/weaknesses/arcane.png",
	GameEnums.Energy.TOXIC: "res://assets/sprites/ui/weaknesses/toxic.png",
}

## DEV : écran de sélection des scénarios, cible du bouton MENU (comme dans le HUD
## d'exploration) tant que la pause de rencontre n'existe pas.
const SCENARIO_SELECT := "res://scenes/dev/scenario_select.tscn"

## Largeur du journal adossé en vue de test.
const DEBUG_LOG_WIDTH := 380.0

## Vue de test : révèle la densité et la faiblesse des rivaux même hors encyclopédie, et
## adosse le journal au bord droit en permanence. Rien de tout ça n'est destiné au
## joueur — d'où l'adossement à [method OS.is_debug_build], qui l'éteint tout seul dans
## un export release. Bascule à chaud avec F1.
var _debug_view := OS.is_debug_build()

@onready var _manager: EncounterManager = $EncounterManager
@onready var _rivals_row: HBoxContainer = $Root/Rivals
@onready var _timeline_row: HBoxContainer = $Root/Timeline
@onready var _log_button: Button = $Root/Corner/LogButton
@onready var _menu_button: Button = $Root/Corner/MenuButton
@onready var _prompt: Label = $Root/Bottom/Prompt
@onready var _description: Label = $Root/Bottom/Description
@onready var _action_bar: HBoxContainer = $Root/Bottom/ActionBar
@onready var _options: VBoxContainer = $Root/Bottom/Options
@onready var _log_panel: PanelContainer = $Root/LogPanel
@onready var _turn_label: Label = $Root/LogPanel/VBox/TurnLabel
@onready var _log: RichTextLabel = $Root/LogPanel/VBox/Log
@onready var _result_label: Label = $Root/Result

var _result := &""
var _awaiting_close := false

## Combattant dont c'est le tour, ou null hors choix : la timeline s'en sert pour savoir
## quelle case agrandir.
var _acting_fighter: EncounterFighter = null

## Un seul agent pour tout le duo : [member UiAgent.pending_fighter] dit de qui c'est le tour.
var _agent := UiAgent.new()

## Fighters joueurs avec leur emplacement de duo, pour réécrire le DEN/ETH persistant
## dans [GameSession] à la fin de la rencontre. Liste de { fighter, slot }.
var _player_slots: Array = []

## Configure et lance la rencontre. `player_ids`/`rival_ids` = slugs d'espèces.
## Point d'intégration persistance : les fighters JOUEURS sont initialisés depuis le
## DEN/ETH persistant de leur emplacement ([GameSession]) et réécrits à la fin
## ([method _sync_back_to_session]). Les rivaux gardent leurs stats placeholder.
func begin(player_ids: Array, rival_ids: Array, completed: Dictionary = {},
		rival_states: Array = []) -> void:
	var pf: Array = []
	for i in player_ids.size():
		var f := EncounterManager.make_fighter(StringName(player_ids[i]), true)
		if f:
			pf.append(f)
			# Index 0 = personnage principal, 1 = coéquipier (cf. Exploration._player_duo).
			# Repli sur MAIN au-delà du duo standard (ne devrait pas arriver).
			var slot := GameSession.PartySlot.TEAMMATE if i == 1 else GameSession.PartySlot.MAIN
			f.load_persistent_state(GameSession.get_den(slot), GameSession.get_eth(slot))
			_player_slots.append({"fighter": f, "slot": slot})
	var rf: Array = []
	for i in rival_ids.size():
		var f := EncounterManager.make_fighter(StringName(rival_ids[i]), false)
		if f == null:
			continue
		# État de carte : le MAXIMUM est un réglage de level design (les ordres de grandeur de
		# la doc sont dans GameSession.RIVAL_DEN_*), et le courant reporte les dégâts déjà subis
		# en exploration (doc « Rivals »). Poser le max AVANT le report, qui borne à ce max.
		var state: Dictionary = rival_states[i] if i < rival_states.size() else {}
		var map_max: int = int(state.get("max_den", 0))
		if map_max > 0:
			f.max_den = map_max
			f.den = map_max
		var map_den: int = int(state.get("den", 0))
		if map_den > 0:
			f.load_persistent_state(map_den, f.max_eth)
		rf.append(f)

	_manager.turn_taken.connect(_on_turn_taken)
	_manager.ended.connect(_on_ended)
	_manager.ifp_earned.connect(_on_ifp_earned)
	_manager.object_consumed.connect(_on_object_consumed)
	# Le manager ignore les autoloads : on lui injecte de quoi résoudre un slug d'objet.
	_manager.object_provider = func(id: StringName) -> ObjectData: return GameData.object(id)
	_manager.setup(pf, rf, randi())
	# APRÈS setup() : il réinitialise les agents. Le duo devient pilotable, les rivaux
	# gardent l'agent auto par défaut du manager.
	_agent.choice_requested.connect(_on_choice_requested)
	for f in pf:
		_manager.set_agent(f, _agent)

	_log_button.pressed.connect(_toggle_log)
	_log_button.text = tr("UI_ENCOUNTER_LOG")
	# MENU ouvrira la pause de rencontre (Monstropaedia / Réglages / Leave The Gloom). Aucun
	# de ces écrans n'existe encore : tant qu'on teste des scénarios, il ramène à l'écran de
	# sélection, comme le bouton MENU du HUD d'exploration. Surtout pas `disabled` : un bouton
	# désactivé est sauté par la navigation clavier, donc injoignable au Tab.
	_menu_button.text = tr("UI_ENCOUNTER_MENU")
	_menu_button.pressed.connect(_on_menu_pressed)

	_apply_debug_view()
	_build_rival_art(rf)
	_refresh_timeline()
	_append("[b]Rencontre[/b] : %s contre %s\n" % [_names(pf), _names(rf)])
	_manager.start()

# --- Mise en page : planches des rivaux, timeline, journal ---

## Pleines planches des rivaux, au centre de l'écran (mockup : jusqu'à 3 de front).
func _build_rival_art(rivals: Array) -> void:
	for c in _rivals_row.get_children():
		c.queue_free()
	for r in rivals:
		var fighter: EncounterFighter = r
		var art := TextureRect.new()
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.custom_minimum_size = Vector2(260, 320)
		var path := "res://assets/sprites/spirimonsters/%s.png" % fighter.species_id()
		if ResourceLoader.exists(path):
			art.texture = load(path)
		art.set_meta("fighter", fighter)
		_rivals_row.add_child(art)

## Reconstruit la timeline dans l'ordre du tour courant. Appelée à chaque tour joué :
## l'ordre lui-même est modifiable en cours de rencontre (Shuffle, Tumult…).
func _refresh_timeline() -> void:
	for c in _timeline_row.get_children():
		c.queue_free()
	var order: Array = _manager.timeline.order if _manager.timeline else []
	for i in order.size():
		var fighter: EncounterFighter = order[i]
		var entry := TimelineEntry.new()
		_timeline_row.add_child(entry)
		var position := _manager.timeline.position_of(fighter)
		entry.setup(fighter, _knows(fighter), fighter == _acting_fighter,
			fighter.active_weakness(position), (i + 1) if _debug_view else 0)
	# Planches des rivaux dissous : estompées, comme leur case de timeline.
	for c in _rivals_row.get_children():
		var art := c as TextureRect
		if art and art.has_meta("fighter"):
			var f: EncounterFighter = art.get_meta("fighter")
			art.modulate.a = 0.25 if f.is_dissolved() else 1.0

## Espèce enregistrée dans l'encyclopédie ? Conditionne l'affichage de la densité et de
## la faiblesse d'un rival dans la timeline (règle doc). La vue de test lève le voile.
func _knows(fighter: EncounterFighter) -> bool:
	return _debug_view or fighter.is_player or GameSession.knows_species(fighter.species_id())

## MENU (DEV) : retour à l'écran de sélection des scénarios.
##
## La rencontre est FERMÉE d'abord : son overlay vit sous `/root` et non dans la scène
## courante, un simple changement de scène le laisserait affiché par-dessus le nouvel écran.
## Émettre `finished` passe par le démontage normal de [TransitionManager] (overlay libéré,
## exploration dépausée), après quoi le changement de scène emporte l'exploration.
## ## TODO: brancher la vraie pause (Monstropaedia / Réglages / Leave The Gloom).
func _on_menu_pressed() -> void:
	finished.emit(&"menu")
	TransitionManager.change_scene(SCENARIO_SELECT)

func _toggle_log() -> void:
	_log_panel.visible = not _log_panel.visible
	_update_turn_label()

func _update_turn_label() -> void:
	if not _log_panel.visible:
		return
	_turn_label.text = tr("UI_ENCOUNTER_TURN") % _manager.round_number
	if _debug_view:
		_turn_label.text += "  ·  F1"

## Applique (ou retire) la disposition de test : journal adossé au bord droit, ouvert en
## permanence, plutôt que le panneau central modal qu'ouvre le bouton JOURNAL.
func _apply_debug_view() -> void:
	if _debug_view:
		_log_panel.anchor_left = 1.0
		_log_panel.anchor_top = 0.0
		_log_panel.anchor_right = 1.0
		_log_panel.anchor_bottom = 1.0
		_log_panel.offset_left = -DEBUG_LOG_WIDTH
		_log_panel.offset_top = 12.0
		_log_panel.offset_right = -12.0
		_log_panel.offset_bottom = -12.0
		_log_panel.visible = true
	else:
		# Retour au panneau centré défini dans la scène.
		_log_panel.anchor_left = 0.5
		_log_panel.anchor_top = 0.5
		_log_panel.anchor_right = 0.5
		_log_panel.anchor_bottom = 0.5
		_log_panel.offset_left = -420.0
		_log_panel.offset_top = -240.0
		_log_panel.offset_right = 420.0
		_log_panel.offset_bottom = 200.0
		_log_panel.visible = false
	_update_turn_label()

func _toggle_debug_view() -> void:
	_debug_view = not _debug_view
	_apply_debug_view()
	_refresh_timeline()

# --- Menu : actions -> (capacités) -> cibles ---
#
# Liste d'actions de la doc Notion (Game Design / Encounters). Règle d'affichage de la
# doc UI : « Unusable actions remain visible in the list, but greyed » — on grise, on ne
# masque jamais. L'action « … » n'est ajoutée EN TÊTE que si plus rien n'est disponible.
#
# Flee / Steal ([constant EncounterAction.Kind.FLEE] / [constant EncounterAction.Kind.STEAL])
# ne sont PAS des actions de base : un talent les AJOUTE au menu (run_away_2, slick_merchant,
# steal), en remplaçant Talk / Use Ability. La liste des kinds offerts est calculée par
# [method EncounterManager.menu_kinds] (qui applique les talents du fighter) ; le menu ci-dessous
# n'affiche que les kinds présents — une action retirée par un talent est absente, pas grisée.

func _on_choice_requested(fighter: EncounterFighter, manager: EncounterManager) -> void:
	_acting_fighter = fighter
	_refresh_timeline()  # la case du combattant actif change de gabarit
	_show_actions(fighter, manager)

## Barre d'actions horizontale du mockup, dans son ordre :
## MEDITATE · CHALLENGE · TALK · EXAMINE · OBJECTS.
func _show_actions(fighter: EncounterFighter, manager: EncounterManager) -> void:
	_prompt.text = tr("UI_ENCOUNTER_CHOOSE_ACTION") % [fighter.display_name(), fighter.eth, fighter.max_eth]
	_clear_options()
	_clear_bar()
	_description.visible = false
	var foes := manager.living_opponents(fighter)
	# Actions de base APRÈS mutation par les talents : ABILITY/TALK peuvent être retirés
	# (remplacés), FLEE/STEAL ajoutés — run_away_2, steal, slick_merchant. Une action retirée
	# par un talent n'est pas grisée mais ABSENTE : le talent la remplace, il ne la bride pas.
	var kinds := manager.menu_kinds(fighter)

	# Meditate n'a ni coût ni cible, aucun talent ne le touche : filet de sécurité du joueur.
	_add_bar_action(tr("UI_ENCOUNTER_ACTION_MEDITATE"), true,
		func(): _submit(EncounterAction.of_kind(EncounterAction.Kind.MEDITATE, [fighter])))
	if kinds.has(EncounterAction.Kind.ABILITY):
		_add_bar_action(tr("UI_ENCOUNTER_ACTION_ABILITY"), not manager.usable_abilities(fighter).is_empty(),
			func(): _show_abilities(fighter, manager))
	if kinds.has(EncounterAction.Kind.TALK):
		# Cibles de Talk élargies aux alliés si un talent l'autorise (Serene Waves).
		var talkable := manager.talk_targets(fighter)
		_add_bar_action(tr("UI_ENCOUNTER_ACTION_TALK"), not talkable.is_empty(),
			func(): _pick_target(fighter, manager, EncounterAction.Kind.TALK, tr("UI_ENCOUNTER_ACTION_TALK"), talkable))
	if kinds.has(EncounterAction.Kind.EXAMINE):
		_add_bar_action(tr("UI_ENCOUNTER_ACTION_EXAMINE"), not foes.is_empty(),
			func(): _pick_target(fighter, manager, EncounterAction.Kind.EXAMINE, tr("UI_ENCOUNTER_ACTION_EXAMINE"), foes))
	_add_bar_action(tr("UI_ENCOUNTER_ACTION_OBJECT"), not GameSession.inventory.is_empty(),
		func(): _show_objects(fighter, manager))
	# Actions AJOUTÉES par un talent (jamais de base) :
	if kinds.has(EncounterAction.Kind.FLEE):
		# Run Away : sans cible (quitter la rencontre). La fuite réelle est encore un stub.
		_add_bar_action(tr("UI_ENCOUNTER_ACTION_FLEE"), true,
			func(): _submit(EncounterAction.of_kind(EncounterAction.Kind.FLEE)))
	if kinds.has(EncounterAction.Kind.STEAL):
		# Steal (granop) : vise un rival, comme Examine.
		_add_bar_action(tr("UI_ENCOUNTER_ACTION_STEAL"), not foes.is_empty(),
			func(): _pick_target(fighter, manager, EncounterAction.Kind.STEAL, tr("UI_ENCOUNTER_ACTION_STEAL"), foes))

	var first := _first_enabled(_action_bar)
	if first == null:
		# « If for some reason no action is available (not even Meditate), a “…” action is
		# added on top of the list » — passe le tour en gardant sa place dans l'ordre.
		var pass_btn := _add_bar_action(tr("UI_ENCOUNTER_ACTION_PASS"), true,
			func(): _submit(EncounterAction.of_kind(EncounterAction.Kind.PASS)))
		_action_bar.move_child(pass_btn, 0)
		first = pass_btn
	_action_bar.visible = true
	first.grab_focus()  # « TALK » encadré du mockup : il y a toujours un focus visible

## Cible d'une action non-combat parmi `targets` : immédiate s'il n'y en a qu'une, sinon
## étape de choix. Utilisé par Talk (cibles possiblement élargies aux alliés), Examine, Steal.
func _pick_target(fighter: EncounterFighter, manager: EncounterManager, kind: EncounterAction.Kind, title: String, targets: Array) -> void:
	if targets.size() <= 1:
		_submit(EncounterAction.of_kind(kind, targets))
		return
	_show_targets(title, targets,
		func(t): return EncounterAction.of_kind(kind, [t]),
		func(): _show_actions(fighter, manager))

func _show_abilities(fighter: EncounterFighter, manager: EncounterManager) -> void:
	_prompt.text = tr("UI_ENCOUNTER_CHOOSE_ABILITY") % [fighter.display_name(), fighter.eth, fighter.max_eth]
	_open_submenu()
	# Les capacités non payables restent visibles mais grisées : le joueur doit voir ce
	# que son ETH lui coûte, pas le déduire d'une liste qui rétrécit.
	for a in manager.encounter_abilities(fighter):
		var ability: AbilityData = a
		var btn := _add_option(_ability_label(ability), func(): _on_ability_chosen(fighter, manager, ability))
		_set_energy_icon(btn, ability.energy)
		btn.disabled = not fighter.can_afford(ability)
		# « Ability description text area » du mockup : la description suit le focus.
		btn.focus_entered.connect(func(): _set_description(tr(ability.desc_key())))
		btn.mouse_entered.connect(func(): _set_description(tr(ability.desc_key())))
	_add_option(tr("UI_ENCOUNTER_BACK"), func(): _show_actions(fighter, manager))
	_focus_first_option()

## Inventaire en rencontre. La cible peut être soi/son coéquipier (« Use ») ou un rival
## (« Give ») : on propose donc les deux camps, contrairement au ciblage des capacités.
func _show_objects(fighter: EncounterFighter, manager: EncounterManager) -> void:
	_prompt.text = tr("UI_ENCOUNTER_CHOOSE_OBJECT") % fighter.display_name()
	_open_submenu()
	for id in GameSession.inventory:
		var obj: ObjectData = GameData.object(id)
		if obj == null:
			continue  # slug d'inventaire sans ObjectData généré : on ne l'invente pas.
		var count: int = GameSession.inventory[id]
		var object_id: StringName = id
		_add_option("%s ×%d" % [tr(obj.name_key()), count],
			func(): _on_object_chosen(fighter, manager, object_id))
	_add_option(tr("UI_ENCOUNTER_BACK"), func(): _show_actions(fighter, manager))
	_focus_first_option()

func _on_object_chosen(fighter: EncounterFighter, manager: EncounterManager, object_id: StringName) -> void:
	var obj: ObjectData = GameData.object(object_id)
	var targets := manager.living_opponents(fighter) + manager.allies_of(fighter).filter(
		func(f): return not f.is_dissolved())
	if targets.size() <= 1:
		var action := EncounterAction.of_kind(EncounterAction.Kind.USE_OBJECT, targets)
		action.object_id = object_id
		_submit(action)
		return
	_show_targets(tr(obj.name_key()), targets,
		func(t):
			var a := EncounterAction.of_kind(EncounterAction.Kind.USE_OBJECT, [t])
			a.object_id = object_id
			return a,
		func(): _show_objects(fighter, manager))

func _ability_label(ability: AbilityData) -> String:
	var name := tr(ability.name_key())
	# Énergies sans icône : on les signale dans le libellé pour qu'on sache toujours l'énergie.
	if ability.energy == GameEnums.Energy.RANDOM:
		name += " " + tr("UI_ENERGY_RANDOM")
	elif ability.energy == GameEnums.Energy.VARIABLE:
		name += " " + tr("UI_ENERGY_VARIABLE")
	return name if ability.eth_cost() == 0 else "%s — ETH %d" % [name, ability.eth_cost()]

## Pose l'icône d'énergie (ancien jeu d'icônes) à gauche du bouton de capacité, bornée en
## largeur pour ne pas envahir le bouton. RANDOM/VARIABLE/NONE n'ont pas d'icône (cf.
## [method _ability_label] pour leur mention texte).
func _set_energy_icon(btn: Button, energy: GameEnums.Energy) -> void:
	if ENERGY_ICONS.has(energy):
		btn.icon = load(ENERGY_ICONS[energy])
		btn.add_theme_constant_override("icon_max_width", 22)

func _on_ability_chosen(fighter: EncounterFighter, manager: EncounterManager, ability: AbilityData) -> void:
	var targets := manager.candidate_targets(fighter, ability)
	if targets.size() <= 1:
		# Cible unique (capacité de soutien sur soi) ou plus personne à viser : aucun choix.
		_submit(EncounterAction.use_ability(ability, targets))
		return
	_show_targets(tr(ability.name_key()), targets,
		func(t): return EncounterAction.use_ability(ability, [t]),
		func(): _show_abilities(fighter, manager))

## Étape de ciblage générique. `make_action` construit l'action pour la cible choisie ;
## `on_back` rouvre le menu d'où l'on vient.
func _show_targets(title: String, targets: Array, make_action: Callable, on_back: Callable) -> void:
	_prompt.text = tr("UI_ENCOUNTER_CHOOSE_TARGET") % title
	_open_submenu()
	for t in targets:
		var target: EncounterFighter = t
		# En vue de test, préfixe le NUMÉRO d'ordre du tour (comme la timeline) : les portraits
		# étant vides tant que les sprites n'existent pas, c'est le seul moyen de distinguer deux
		# cibles de même espèce (« draka, draka »). Retiré hors debug — en version finale les
		# sprites des personnages suffiront à identifier la cible.
		var label := "%s — DEN %d/%d" % [target.display_name(), target.den, target.max_den]
		if _debug_view:
			label = "%d · %s" % [_turn_number(target), label]
		var btn := _add_option(label, func(): _submit(make_action.call(target)))
		# Surlignage de la cible visée, version sobre du mockup (qui prévoit en plus une
		# flèche sautillante et un léger zoom sur la planche) : la planche du rival visé
		# s'éclaircit au survol, et la timeline le met en avant.
		btn.focus_entered.connect(func(): _highlight_target(target))
		btn.mouse_entered.connect(func(): _highlight_target(target))
	_add_option(tr("UI_ENCOUNTER_BACK"), on_back)
	_focus_first_option()

## Position (1-based) d'un combattant dans l'ordre du tour — même numéro que la timeline en
## vue de test. 0 si introuvable (ne devrait pas arriver pour une cible en lice).
func _turn_number(fighter: EncounterFighter) -> int:
	var order: Array = _manager.timeline.order if _manager.timeline else []
	return order.find(fighter) + 1

## Éclaircit la planche du rival visé et estompe les autres.
func _highlight_target(target: EncounterFighter) -> void:
	for c in _rivals_row.get_children():
		var art := c as TextureRect
		if art == null or not art.has_meta("fighter"):
			continue
		var f: EncounterFighter = art.get_meta("fighter")
		if f.is_dissolved():
			continue
		art.modulate = Color(1, 1, 1) if f == target else Color(0.55, 0.55, 0.6)

func _clear_highlight() -> void:
	for c in _rivals_row.get_children():
		var art := c as TextureRect
		if art and art.has_meta("fighter"):
			art.modulate = Color(1, 1, 1)

func _submit(action: EncounterAction) -> void:
	_close_menu()
	_agent.submit(action)

func _close_menu() -> void:
	_acting_fighter = null
	_action_bar.visible = false
	_description.visible = false
	_prompt.text = ""
	_clear_bar()
	_clear_options()
	_clear_highlight()

## Ouvre une liste verticale de sous-choix : elle remplace la barre d'actions, qui n'a
## pas la place d'afficher une dizaine de capacités de front.
func _open_submenu() -> void:
	_clear_options()
	_clear_bar()
	_action_bar.visible = false
	_clear_highlight()
	_set_description("")

func _set_description(text: String) -> void:
	_description.text = text
	_description.visible = text != ""

func _clear_options() -> void:
	for c in _options.get_children():
		_options.remove_child(c)
		c.queue_free()

func _clear_bar() -> void:
	for c in _action_bar.get_children():
		_action_bar.remove_child(c)
		c.queue_free()

func _add_option(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(on_press)
	_options.add_child(b)
	return b

## Bouton de la barre d'actions. Grisé mais TOUJOURS visible s'il est indisponible :
## « Unusable actions remain visible in the list, but greyed ».
func _add_bar_action(text: String, enabled: bool, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text.to_upper()  # la casse est un parti pris visuel, pas une chaîne traduite
	b.flat = true
	b.disabled = not enabled
	b.pressed.connect(on_press)
	_action_bar.add_child(b)
	return b

func _focus_first_option() -> void:
	var first := _first_enabled(_options)
	if first:
		first.grab_focus()

## Premier bouton cliquable d'un conteneur, ou null s'il n'y en a aucun.
func _first_enabled(container: Node) -> Button:
	for c in container.get_children():
		if c is Button and not c.disabled:
			return c
	return null

func _on_turn_taken(fighter: EncounterFighter, action: EncounterAction, lines: PackedStringArray) -> void:
	# Un en-tête lisible par tour, puis les effets indentés dessous. Une capacité comme
	# Opening up Closing produit plusieurs effets (dégâts, dégâts, fuite) : ils se lisent
	# ainsi comme UNE action, au lieu d'une pile de lignes préfixées à l'identique.
	_append("[b]%s[/b] — %s" % [fighter.display_name(), _action_verb(action)])
	for l in lines:
		_append("    [color=#b9b9c4]%s[/color]" % l)
	# DEN/ETH, dissolutions et réordonnancements ont pu bouger : la timeline se relit.
	_refresh_timeline()
	_update_turn_label()

## Nom lisible et traduit de l'action, pour l'en-tête du journal. `action.label()` ne
## sert plus qu'au journal debug interne du manager (id brut / nom d'enum).
func _action_verb(action: EncounterAction) -> String:
	match action.kind:
		EncounterAction.Kind.ABILITY:
			return tr(action.ability.name_key()) if action.ability else "?"
		EncounterAction.Kind.MEDITATE:
			return tr("UI_ENCOUNTER_ACTION_MEDITATE")
		EncounterAction.Kind.TALK:
			return tr("UI_ENCOUNTER_ACTION_TALK")
		EncounterAction.Kind.EXAMINE:
			return tr("UI_ENCOUNTER_ACTION_EXAMINE")
		EncounterAction.Kind.USE_OBJECT:
			return tr("UI_ENCOUNTER_ACTION_OBJECT")
		EncounterAction.Kind.FLEE:
			return tr("UI_ENCOUNTER_ACTION_FLEE")
		EncounterAction.Kind.STEAL:
			return tr("UI_ENCOUNTER_ACTION_STEAL")
		_:
			return tr("UI_ENCOUNTER_ACTION_PASS")

## Le manager signale les IFP gagnés ; c'est ici qu'ils rejoignent l'encyclopédie, avec
## les trois restrictions déjà portées par [method GameSession.award_ifp].
func _on_ifp_earned(species_id: StringName, action: GameEnums.IfpAction, is_forlorn: bool, dialogue_effective: bool) -> void:
	var gained := GameSession.award_ifp(species_id, action, is_forlorn, dialogue_effective)
	if gained > 0:
		var sp: SpeciesData = GameData.species(species_id)
		var sp_name := tr(sp.name_key()) if sp else String(species_id)
		_append("    [color=#c9b060][i]+%d IFP — %s[/i][/color]" % [gained, sp_name])

## « Objects are all consumable items (removed from inventory after use) ».
func _on_object_consumed(object_id: StringName) -> void:
	GameSession.remove_object(object_id)

func _on_ended(result: StringName) -> void:
	_result = result
	_close_menu()
	# Compteur FDE (« murderous spree ») : une rencontre où TOUS les rivaux sont dissous
	# incrémente, toute autre issue remet à zéro.
	GameSession.register_encounter_end(_manager.rivals.all(func(f): return f.is_dissolved()))
	_sync_back_to_session()
	_append("\n[b]→ %s[/b]" % result)
	_refresh_timeline()
	if _result_label:
		_result_label.text = tr("UI_ENCOUNTER_RESULT_%s" % result.to_upper()) \
			+ "\n" + tr("UI_ENCOUNTER_CONTINUE")
	_awaiting_close = true

## Réécrit le DEN/ETH final des fighters joueurs dans [GameSession] (persistance des
## dégâts subis). N'altère PAS les rivaux. À appeler une fois la rencontre résolue.
func _sync_back_to_session() -> void:
	for entry in _player_slots:
		var f: EncounterFighter = entry["fighter"]
		var slot: GameSession.PartySlot = entry["slot"]
		GameSession.set_den(slot, f.den)
		GameSession.set_eth(slot, f.eth)

func _unhandled_input(event: InputEvent) -> void:
	# F1 : bascule la vue de test. Touche brute plutôt qu'une action de project.godot —
	# c'est un outil de développement, pas une commande de jeu à remapper.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
		_toggle_debug_view()
		get_viewport().set_input_as_handled()
		return
	if _awaiting_close and (event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel") \
			or (event is InputEventMouseButton and event.pressed)):
		_awaiting_close = false
		finished.emit(_result)

func _append(line: String) -> void:
	if _log:
		_log.append_text(line + "\n")

func _names(fighters: Array) -> String:
	return ", ".join(fighters.map(func(f): return f.display_name()))
