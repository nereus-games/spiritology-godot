## The encounter screen — a 2D overlay above the running exploration scene.
##
## The player's duo is driven by a single [UiAgent]: on each of their turns the
## [EncounterManager] loop suspends, the menu opens, and the submitted choice resumes it.
## Rivals keep the manager's automatic agent. [signal finished] tells [TransitionManager]
## to tear the overlay down and unpause exploration.
##
## Layout follows the design doc's mockup (User Interface / Encounters): LOG and MENU top
## left, the turn order across the top with one cell per individual, the rivals' full artwork
## in the centre, and at the bottom a horizontal action bar that gives way to a vertical
## list for sub-choices.
##
## The log is a panel you open rather than a permanent fixture, with the round number
## pinned outside the scroll.
extends CanvasLayer

signal finished(result: StringName)

## Preloaded rather than named: see that script's header.
const TimelineEntry := preload("res://scripts/ui/encounter_timeline_entry.gd")
const MenuPanel := preload("res://scripts/ui/encounter_menu_panel.gd")

## Where MENU goes for now, since the encounter pause screen does not exist.
const SCENARIO_SELECT := "res://scenes/dev/scenario_select.tscn"

## Width of the docked log in the debug view.
const DEBUG_LOG_WIDTH := 380.0

## Debug view: shows rivals' density and weakness even when the encyclopaedia would hide
## them, and docks the log permanently to the right edge. None of it is meant for players,
## which is why it hangs off [method OS.is_debug_build] and switches itself off in a
## release export. F1 toggles it live.
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

## The bottom panel. Built in _ready(), because @onready fields are not resolved yet when
## the members above are initialised.
var _menu: MenuPanel

var _result := &""
var _awaiting_close := false

## Whose turn it is, or null between choices. The turn order uses it to enlarge a cell.
var _acting_individual: EncounterIndividual = null

## One agent for the whole duo; [member UiAgent.pending_individual] says whose turn it is.
var _agent := UiAgent.new()

## Player individuals paired with their party slot, so DEN/ETH can be written back to
## [GameSession] when the encounter ends.
var _player_slots: Array = []


func _ready() -> void:
	_menu = MenuPanel.new(_prompt, _description, _action_bar, _options)


## Closes the menu and hands the screen back to the encounter: the panel empties, the
## screen forgets who was acting, and the target highlight goes out.
func _close_menu() -> void:
	_acting_individual = null
	_menu.clear()
	_clear_highlight()


## Sets up and starts the encounter.
##
## The persistence seam: PLAYER individuals are seeded from their slot's stored DEN/ETH and
## written back at the end ([method _sync_back_to_session]), so damage carries between
## encounters. Rivals keep their own stats.
func begin(
	player_ids: Array,
	rival_ids: Array,
	_completed: Dictionary = {},
	rival_states: Array = [],
	seed: int = -1
) -> void:
	var pf: Array = []
	for i in player_ids.size():
		var f := EncounterManager.make_individual(StringName(player_ids[i]), true)
		if f:
			pf.append(f)
			# 0 is the main character, 1 the teammate. Anything beyond a duo falls back to
			# MAIN, which should not happen.
			var slot := GameSession.PartySlot.TEAMMATE if i == 1 else GameSession.PartySlot.MAIN
			f.load_persistent_state(GameSession.get_den(slot), GameSession.get_eth(slot))
			_player_slots.append({"individual": f, "slot": slot})
	var rf: Array = []
	for i in rival_ids.size():
		var f := EncounterManager.make_individual(StringName(rival_ids[i]), false)
		if f == null:
			continue
		# Map state: the MAXIMUM is a level design setting (the doc's magnitudes are in
		# GameSession.RIVAL_DEN_*), while the current value carries over damage already
		# taken while exploring. Set the max FIRST — the carry-over clamps to it.
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
	# The manager knows no autoloads, so it is handed a way to resolve object slugs.
	_manager.object_provider = func(id: StringName) -> ObjectData: return GameData.object(id)
	# A negative `seed` means an ordinary encounter, with the turn order drawn at random.
	# Fixing it makes the whole encounter reproducible, which is what the screenshot scene
	# needs for one version to be comparable with the next.
	_manager.setup(pf, rf, randi() if seed < 0 else seed)
	# AFTER setup(), which resets the agents. Only the duo becomes playable.
	_agent.choice_requested.connect(_on_choice_requested)
	for f in pf:
		_manager.set_agent(f, _agent)

	_log_button.pressed.connect(_toggle_log)
	_log_button.text = tr("UI_ENCOUNTER_LOG")
	# MENU will open the encounter pause — Monstropaedia, Settings, Leave The Gloom. None of
	# those screens exists, so for now it returns to the scenario picker. Deliberately not
	# `disabled`: a disabled button is skipped by keyboard navigation and becomes
	# unreachable by Tab.
	_menu_button.text = tr("UI_ENCOUNTER_MENU")
	_menu_button.pressed.connect(_on_menu_pressed)

	_apply_debug_view()
	_build_rival_art(rf)
	_refresh_timeline()
	var opening := tr("LOG_ENCOUNTER_OPENING") % [_names(pf), _names(rf)]
	_append("[b]%s[/b]%s\n" % [tr("TERM_ENCOUNTER"), opening])
	_manager.start()


# --- Layout: rival artwork, turn order, log ---


## The rivals' full artwork, centre screen — up to three abreast in the mockup.
func _build_rival_art(rivals: Array) -> void:
	for c in _rivals_row.get_children():
		c.queue_free()
	for r in rivals:
		var individual: EncounterIndividual = r
		var art := TextureRect.new()
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.custom_minimum_size = Vector2(260, 320)
		var path := "res://assets/sprites/spirimonsters/%s.png" % individual.species_id()
		if ResourceLoader.exists(path):
			art.texture = load(path)
		art.set_meta("individual", individual)
		_rivals_row.add_child(art)


## Rebuilds the turn order display. Called after every turn, because the order itself can
## change mid-encounter.
func _refresh_timeline() -> void:
	for c in _timeline_row.get_children():
		c.queue_free()
	var order: Array = _manager.timeline.order if _manager.timeline else []
	for i in order.size():
		var individual: EncounterIndividual = order[i]
		var entry := TimelineEntry.new()
		_timeline_row.add_child(entry)
		var position := _manager.timeline.position_of(individual)
		entry.setup(
			individual,
			_knows(individual),
			individual == _acting_individual,
			individual.active_weakness(position),
			(i + 1) if _debug_view else 0
		)
	# A dissolved rival fades, like its cell in the turn order.
	for c in _rivals_row.get_children():
		var art := c as TextureRect
		if art and art.has_meta("individual"):
			var f: EncounterIndividual = art.get_meta("individual")
			art.modulate.a = 0.25 if f.is_dissolved() else 1.0


## Whether the species is in the encyclopaedia at all, which is what the doc makes the
## display of a rival's density and weakness depend on. The debug view lifts the veil.
func _knows(individual: EncounterIndividual) -> bool:
	return _debug_view or individual.is_player or GameSession.knows_species(individual.species_id())


## Back to the scenario picker.
##
## The encounter is CLOSED first. Its overlay lives under `/root` rather than in the current
## scene, so a plain scene change would leave it drawn on top of the new screen. Emitting
## `finished` goes through [TransitionManager]'s normal teardown, after which changing the
## scene takes exploration with it.
## ## TODO: wire the real pause screen.
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


## Applies or removes the debug layout: the log docked to the right edge and permanently
## open, instead of the modal centre panel the LOG button opens.
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
		# Back to the centred panel the scene defines.
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


# --- The menu: actions -> (abilities) -> targets ---
#
# The action list comes from the design doc, and so does the display rule: "Unusable
# actions remain visible in the list, but greyed" — grey them, never hide them. The "…"
# action is added ON TOP, and only when nothing else is available at all.
#
# Flee and Steal are NOT base actions: a talent ADDS them, replacing Talk or Use Ability.
# [method EncounterManager.menu_kinds] applies the individual's talents and returns what is
# actually on offer; an action a talent removed is ABSENT, not greyed, because the talent
# replaces it rather than forbidding it.


func _on_choice_requested(individual: EncounterIndividual, manager: EncounterManager) -> void:
	_acting_individual = individual
	_refresh_timeline()  # the active individual's cell changes size
	_show_actions(individual, manager)


## The mockup's horizontal action bar, in its order:
## MEDITATE · CHALLENGE · TALK · EXAMINE · OBJECTS.
func _show_actions(individual: EncounterIndividual, manager: EncounterManager) -> void:
	_menu.set_prompt(
		(
			tr("UI_ENCOUNTER_CHOOSE_ACTION")
			% [individual.display_name(), individual.eth, individual.max_eth]
		)
	)
	_menu.clear_options()
	_menu.clear_bar()
	_menu.set_description("")
	var foes := manager.living_opponents(individual)
	# Base actions AFTER the talents have had their say.
	var kinds := manager.menu_kinds(individual)

	# Meditate costs nothing, needs no target, and no talent removes it — the player's
	# safety net.
	_menu.add_bar_action(
		tr("UI_ENCOUNTER_ACTION_MEDITATE"),
		true,
		func(): _submit(EncounterAction.of_kind(EncounterAction.Kind.MEDITATE, [individual]))
	)
	if kinds.has(EncounterAction.Kind.ABILITY):
		_menu.add_bar_action(
			tr("UI_ENCOUNTER_ACTION_ABILITY"),
			not manager.usable_abilities(individual).is_empty(),
			func(): _show_abilities(individual, manager)
		)
	if kinds.has(EncounterAction.Kind.TALK):
		# Serene Waves widens Talk to the teammate.
		var talkable := manager.talk_targets(individual)
		_menu.add_bar_action(
			tr("UI_ENCOUNTER_ACTION_TALK"),
			not talkable.is_empty(),
			func():
				_pick_target(
					individual,
					manager,
					EncounterAction.Kind.TALK,
					tr("UI_ENCOUNTER_ACTION_TALK"),
					talkable
				)
		)
	if kinds.has(EncounterAction.Kind.EXAMINE):
		_menu.add_bar_action(
			tr("UI_ENCOUNTER_ACTION_EXAMINE"),
			not foes.is_empty(),
			func():
				_pick_target(
					individual,
					manager,
					EncounterAction.Kind.EXAMINE,
					tr("UI_ENCOUNTER_ACTION_EXAMINE"),
					foes
				)
		)
	_menu.add_bar_action(
		tr("UI_ENCOUNTER_ACTION_OBJECT"),
		not GameSession.inventory.is_empty(),
		func(): _show_objects(individual, manager)
	)
	# Actions a talent added; never available by default.
	if kinds.has(EncounterAction.Kind.FLEE):
		# Run Away takes no target. Actually leaving is still a stub.
		_menu.add_bar_action(
			tr("UI_ENCOUNTER_ACTION_FLEE"),
			true,
			func(): _submit(EncounterAction.of_kind(EncounterAction.Kind.FLEE))
		)
	if kinds.has(EncounterAction.Kind.STEAL):
		# Steal aims at a rival, like Examine.
		_menu.add_bar_action(
			tr("UI_ENCOUNTER_ACTION_STEAL"),
			not foes.is_empty(),
			func():
				_pick_target(
					individual,
					manager,
					EncounterAction.Kind.STEAL,
					tr("UI_ENCOUNTER_ACTION_STEAL"),
					foes
				)
		)

	var first := _menu.first_enabled_bar_action()
	if first == null:
		# "If for some reason no action is available (not even Meditate), a '…' action is
		# added on top of the list" — passes the turn without losing your place in the
		# order.
		var pass_btn := _menu.add_bar_action(
			tr("UI_ENCOUNTER_ACTION_PASS"),
			true,
			func(): _submit(EncounterAction.of_kind(EncounterAction.Kind.PASS))
		)
		_menu.move_bar_action_first(pass_btn)
		first = pass_btn
	_menu.show_bar(true)
	first.grab_focus()  # the mockup frames "TALK": there is always a visible focus


## Picks the target of a non-combat action: immediate when there is only one, a choice
## otherwise. Used by Talk, Examine and Steal.
func _pick_target(
	individual: EncounterIndividual,
	manager: EncounterManager,
	kind: EncounterAction.Kind,
	title: String,
	targets: Array
) -> void:
	if targets.size() <= 1:
		_submit(EncounterAction.of_kind(kind, targets))
		return
	_show_targets(
		title,
		targets,
		func(t): return EncounterAction.of_kind(kind, [t]),
		func(): _show_actions(individual, manager)
	)


func _show_abilities(individual: EncounterIndividual, manager: EncounterManager) -> void:
	_menu.set_prompt(
		(
			tr("UI_ENCOUNTER_CHOOSE_ABILITY")
			% [individual.display_name(), individual.eth, individual.max_eth]
		)
	)
	_menu.begin_submenu()
	# Unaffordable abilities stay visible and greyed: the player should see what their ETH
	# is costing them, not infer it from a list that quietly shrinks.
	for a in manager.encounter_abilities(individual):
		var ability: AbilityData = a
		var btn := _menu.add_option(
			_ability_label(ability), func(): _on_ability_chosen(individual, manager, ability)
		)
		_menu.set_energy_icon(btn, ability.energy)
		btn.disabled = not individual.can_afford(ability)
		# The mockup's "ability description text area": the description follows the focus.
		btn.focus_entered.connect(func(): _menu.set_description(tr(ability.desc_key())))
		btn.mouse_entered.connect(func(): _menu.set_description(tr(ability.desc_key())))
	_menu.add_option(tr("UI_ENCOUNTER_BACK"), func(): _show_actions(individual, manager))
	_menu.focus_first_option()


## The inventory, in an encounter. The target may be oneself or the teammate ("Use") or a
## rival ("Give"), so both sides are offered — unlike ability targeting.
func _show_objects(individual: EncounterIndividual, manager: EncounterManager) -> void:
	_menu.set_prompt(tr("UI_ENCOUNTER_CHOOSE_OBJECT") % individual.display_name())
	_menu.begin_submenu()
	for id in GameSession.inventory:
		var obj: ObjectData = GameData.object(id)
		if obj == null:
			continue  # an inventory slug with no ObjectData behind it; we do not invent one
		var count: int = GameSession.inventory[id]
		var object_id: StringName = id
		_menu.add_option(
			"%s ×%d" % [tr(obj.name_key()), count],
			func(): _on_object_chosen(individual, manager, object_id)
		)
	_menu.add_option(tr("UI_ENCOUNTER_BACK"), func(): _show_actions(individual, manager))
	_menu.focus_first_option()


func _on_object_chosen(
	individual: EncounterIndividual, manager: EncounterManager, object_id: StringName
) -> void:
	var obj: ObjectData = GameData.object(object_id)
	var targets := (
		manager.living_opponents(individual)
		+ manager.allies_of(individual).filter(func(f): return not f.is_dissolved())
	)
	if targets.size() <= 1:
		var action := EncounterAction.of_kind(EncounterAction.Kind.USE_OBJECT, targets)
		action.object_id = object_id
		_submit(action)
		return
	_show_targets(
		tr(obj.name_key()),
		targets,
		func(t):
			var a := EncounterAction.of_kind(EncounterAction.Kind.USE_OBJECT, [t])
			a.object_id = object_id
			return a,
		func(): _show_objects(individual, manager)
	)


func _ability_label(ability: AbilityData) -> String:
	var name := tr(ability.name_key())
	# Energies with no icon are named in the label instead, so the energy is never a
	# mystery.
	if ability.energy == GameEnums.Energy.RANDOM:
		name += " " + tr("UI_ENERGY_RANDOM")
	elif ability.energy == GameEnums.Energy.VARIABLE:
		name += " " + tr("UI_ENERGY_VARIABLE")
	return name if ability.eth_cost() == 0 else "%s — ETH %d" % [name, ability.eth_cost()]


func _on_ability_chosen(
	individual: EncounterIndividual, manager: EncounterManager, ability: AbilityData
) -> void:
	var targets := manager.candidate_targets(individual, ability)
	if targets.size() <= 1:
		# One target, or none left: nothing to choose.
		_submit(EncounterAction.use_ability(ability, targets))
		return
	_show_targets(
		tr(ability.name_key()),
		targets,
		func(t): return EncounterAction.use_ability(ability, [t]),
		func(): _show_abilities(individual, manager)
	)


## The generic targeting step. `make_action` builds the action for whichever target is
## picked; `on_back` reopens the menu it came from.
func _show_targets(title: String, targets: Array, make_action: Callable, on_back: Callable) -> void:
	_menu.set_prompt(tr("UI_ENCOUNTER_CHOOSE_TARGET") % title)
	_menu.begin_submenu()
	for t in targets:
		var target: EncounterIndividual = t
		# In the debug view, prefix the turn-order NUMBER. With no sprites yet the portraits
		# are blank, and this is the only way to tell two targets of the same species apart
		# ("draka, draka"). Dropped outside debug: the artwork will do the job.
		var label := "%s — DEN %d/%d" % [target.display_name(), target.den, target.max_den]
		if _debug_view:
			label = "%d · %s" % [_turn_number(target), label]
		var btn := _menu.add_option(label, func(): _submit(make_action.call(target)))
		# A restrained version of the mockup's highlight, which also calls for a bouncing
		# arrow and a slight zoom: the aimed-at rival's artwork brightens, and the turn
		# order picks it out.
		btn.focus_entered.connect(func(): _highlight_target(target))
		btn.mouse_entered.connect(func(): _highlight_target(target))
	_menu.add_option(tr("UI_ENCOUNTER_BACK"), on_back)
	_menu.focus_first_option()


## An individual's 1-based place in the turn order — the number the debug view shows.
func _turn_number(individual: EncounterIndividual) -> int:
	var order: Array = _manager.timeline.order if _manager.timeline else []
	return order.find(individual) + 1


## Brightens the aimed-at rival's artwork and dims the rest.
func _highlight_target(target: EncounterIndividual) -> void:
	for c in _rivals_row.get_children():
		var art := c as TextureRect
		if art == null or not art.has_meta("individual"):
			continue
		var f: EncounterIndividual = art.get_meta("individual")
		if f.is_dissolved():
			continue
		art.modulate = Color(1, 1, 1) if f == target else Color(0.55, 0.55, 0.6)


func _clear_highlight() -> void:
	for c in _rivals_row.get_children():
		var art := c as TextureRect
		if art and art.has_meta("individual"):
			art.modulate = Color(1, 1, 1)


func _submit(action: EncounterAction) -> void:
	_close_menu()
	_agent.submit(action)


func _on_turn_taken(
	individual: EncounterIndividual, action: EncounterAction, lines: PackedStringArray
) -> void:
	# One readable header per turn, with the effects indented under it. An ability like
	# Opening up Closing produces several — damage, damage, flee — and this way they read
	# as ONE action instead of a stack of identically prefixed lines.
	_append("[b]%s[/b] — %s" % [individual.display_name(), _action_verb(action)])
	for l in lines:
		_append("    [color=#b9b9c4]%s[/color]" % l)
	# DEN, ETH, dissolutions and reordering may all have moved.
	_refresh_timeline()
	_update_turn_label()


## The action's translated name, for the log header. `action.label()` is now only used by
## the manager's own debug log, where a raw id is what you want.
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


## The manager announces IFP; this is where they reach the encyclopaedia, with the
## restrictions [method GameSession.award_ifp] already enforces.
func _on_ifp_earned(
	species_id: StringName, action: GameEnums.IfpAction, is_forlorn: bool, dialogue_effective: bool
) -> void:
	var gained := GameSession.award_ifp(species_id, action, is_forlorn, dialogue_effective)
	if gained > 0:
		var sp: SpeciesData = GameData.species(species_id)
		var sp_name := tr(sp.name_key()) if sp else String(species_id)
		var gain := tr("LOG_LINE_IFP") % [gained, sp_name]
		_append("    [color=#c9b060][i]%s[/i][/color]" % gain)


## "Objects are all consumable items (removed from inventory after use)".
func _on_object_consumed(object_id: StringName) -> void:
	GameSession.remove_object(object_id)


func _on_ended(result: StringName) -> void:
	_result = result
	_close_menu()
	# The FDE counter — the hidden "murderous spree". Dissolving EVERY rival increments it;
	# any other outcome resets it.
	GameSession.register_encounter_end(_manager.rivals.all(func(f): return f.is_dissolved()))
	_sync_back_to_session()
	_append("\n[b]→ %s[/b]" % tr("UI_ENCOUNTER_RESULT_%s" % result.to_upper()))
	_refresh_timeline()
	if _result_label:
		_result_label.text = (
			tr("UI_ENCOUNTER_RESULT_%s" % result.to_upper()) + "\n" + tr("UI_ENCOUNTER_CONTINUE")
		)
	_awaiting_close = true


## Writes the player individuals' final DEN/ETH back to [GameSession], which is what makes
## damage persist between encounters. Rivals are left alone.
func _sync_back_to_session() -> void:
	for entry in _player_slots:
		var f: EncounterIndividual = entry["individual"]
		var slot: GameSession.PartySlot = entry["slot"]
		GameSession.set_den(slot, f.den)
		GameSession.set_eth(slot, f.eth)


func _unhandled_input(event: InputEvent) -> void:
	# A raw key rather than an action in project.godot: this is a development tool, not a
	# game command anyone should be remapping.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
		_toggle_debug_view()
		get_viewport().set_input_as_handled()
		return
	if (
		_awaiting_close
		and (
			event.is_action_pressed("ui_accept")
			or event.is_action_pressed("ui_cancel")
			or (event is InputEventMouseButton and event.pressed)
		)
	):
		_awaiting_close = false
		finished.emit(_result)


func _append(line: String) -> void:
	if _log:
		_log.append_text(line + "\n")


func _names(individuals: Array) -> String:
	return ", ".join(individuals.map(func(f): return f.display_name()))
