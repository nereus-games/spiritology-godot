## A minimal exploration HUD: the duo's DEN/ETH gauges plus a contextual action menu.
##
## Deliberately built IN CODE and kept minimal — an adjustable placeholder. Shows the duo's two
## slots ([enum GameSession.PartySlot]) with a name, a DEN bar, an ETH bar and current/max text
## (element 2 in the design doc), plus a contextual action menu bottom-left (element 3) fed by
## [method DungeonManager.actions_for] from the player's tile and facing. Navigation:
## `cycle_action` (Tab) cycles, `cycle_action_reverse` (Shift+Tab) cycles back, `interact`
## (Space/Enter) confirms. It updates live from [GameSession]'s DEN/ETH signals.
## TODO, from the design doc's "User Interface": the mini-map (element 1), the stack of known
## exploration abilities (element 4) with its USE/CANCEL submenu, and the final layout (DEN/ETH
## bottom-centre, round icons).
extends CanvasLayer

const ExplorationActionMenu := preload("res://scripts/ui/exploration_action_menu.gd")
const ExplorationContext := preload("res://scripts/exploration/abilities/exploration_context.gd")
const ExplorationExtraActions := preload("res://scripts/exploration/exploration_extra_actions.gd")
const ExplorationAction := preload("res://scripts/exploration/exploration_action.gd")
const ExplorationMinimap := preload("res://scripts/ui/exploration_minimap.gd")

## DEV: the test-scenario selection screen, where the MENU button leads. Temporary.
const SCENARIO_SELECT := "res://scenes/dev/scenario_select.tscn"

## The slots shown, in order: main character then teammate.
const SLOTS: Array[GameSession.PartySlot] = [
	GameSession.PartySlot.MAIN,
	GameSession.PartySlot.TEAMMATE,
]

const DEN_COLOR := Color(0.85, 0.27, 0.30)  ## density (health)
const ETH_COLOR := Color(0.30, 0.62, 0.90)  ## ether (energy)

var _name_label: Dictionary = {}  # slot -> Label
var _den_bar: Dictionary = {}  # slot -> ProgressBar
var _eth_bar: Dictionary = {}  # slot -> ProgressBar
var _den_text: Dictionary = {}  # slot -> Label
var _eth_text: Dictionary = {}  # slot -> Label

var _action_menu: Control
var _dungeon: DungeonManager
var _player: Node
var _extra_actions  # ExplorationExtraActions: exploration abilities and objects

var _balance_bar: ProgressBar
var _status_label: Label

## The one-off message banner — a dieverting's outcome and the like — and its fade-out.
var _message_label: Label
var _message_tween: Tween

## How long a message stays at full opacity, in seconds, then how long the fade takes.
const MESSAGE_HOLD := 4.0
const MESSAGE_FADE := 1.0


func _ready() -> void:
	layer = 10  # above the 3D, below the encounter overlay (TransitionManager)
	_build()
	_build_action_menu()
	_build_balance_bar()
	_build_minimap()
	_build_status()
	_build_message()
	GameSession.den_changed.connect(_on_den_changed)
	GameSession.eth_changed.connect(_on_eth_changed)
	for slot in SLOTS:
		_refresh(slot)


## Builds the UI tree: the DEN/ETH gauges side by side, bottom-centre, as the design doc wants.
func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	row.position.y = -12  # 12 px above the bottom edge
	root.add_child(row)

	for slot in SLOTS:
		row.add_child(_build_slot(slot))


## Builds one slot's panel and remembers its widgets.
func _build_slot(slot: GameSession.PartySlot) -> Control:
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(220, 0)
	box.add_theme_constant_override("separation", 2)
	panel.add_child(box)

	var name_label := Label.new()
	_name_label[slot] = name_label
	box.add_child(name_label)

	box.add_child(_build_bar(slot, "DEN", DEN_COLOR, _den_bar, _den_text))
	box.add_child(_build_bar(slot, "ETH", ETH_COLOR, _eth_bar, _eth_text))
	return panel


## Builds a caption + bar + current/max row, and remembers the bar and the text.
func _build_bar(
	slot: GameSession.PartySlot,
	caption: String,
	color: Color,
	bar_store: Dictionary,
	text_store: Dictionary
) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var caption_label := Label.new()
	caption_label.text = caption
	caption_label.custom_minimum_size = Vector2(34, 0)
	row.add_child(caption_label)

	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(150, 14)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	bar.add_theme_stylebox_override("fill", fill)
	bar_store[slot] = bar
	row.add_child(bar)

	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(56, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	text_store[slot] = value_label
	row.add_child(value_label)
	return row


## Fully refreshes one slot: name, bars and texts.
func _refresh(slot: GameSession.PartySlot) -> void:
	_name_label[slot].text = _slot_name(slot)
	_on_den_changed(slot, GameSession.get_den(slot))
	_on_eth_changed(slot, GameSession.get_eth(slot))


func _on_den_changed(slot: GameSession.PartySlot, value: int) -> void:
	if not _den_bar.has(slot):
		return
	_den_bar[slot].max_value = GameSession.MAX_DEN
	_den_bar[slot].value = value
	_den_text[slot].text = "%d/%d" % [value, GameSession.MAX_DEN]


func _on_eth_changed(slot: GameSession.PartySlot, value: int) -> void:
	if not _eth_bar.has(slot):
		return
	_eth_bar[slot].max_value = GameSession.MAX_ETH
	_eth_bar[slot].value = value
	_eth_text[slot].text = "%d/%d" % [value, GameSession.MAX_ETH]


## The name shown: the slot's species' translated name, or a generic fallback.
func _slot_name(slot: GameSession.PartySlot) -> String:
	var id := (
		GameSession.main_character if slot == GameSession.PartySlot.MAIN else GameSession.teammate
	)
	if id != &"":
		var sp: SpeciesData = GameData.species(id)
		if sp:
			return String(TranslationServer.translate(sp.name_key()))
	return "Personnage %d" % (1 if slot == GameSession.PartySlot.MAIN else 2)


# --------------------------------------------------------------------------
# The contextual action menu (element 3)
# --------------------------------------------------------------------------


## Builds the action menu, full-screen. The list itself anchors bottom-left and grows upwards, so
## every entry stays visible.
func _build_action_menu() -> void:
	_action_menu = ExplorationActionMenu.new()
	_action_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	_action_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_action_menu)


## Asks every frame which contextual actions are available while the player is at rest, and
## updates the menu. The dungeon and the player are resolved lazily, since the HUD can be ready
## before them.
func _process(_delta: float) -> void:
	if _dungeon == null:
		_dungeon = get_tree().get_first_node_in_group("dungeon") as DungeonManager
		if _dungeon != null:
			_dungeon.message_posted.connect(show_message)
	if _player == null:
		_player = get_tree().get_first_node_in_group("player")
	if _dungeon == null or _player == null:
		return
	if _player.is_at_rest():
		_refresh_actions()
	_update_status()


## Rebuilds the menu: the mechanisms' actions, for the current tile and the one being faced, plus
## exploration abilities and objects, through a persistent [ExplorationExtraActions] whose
## callables stay valid as long as the menu shows them.
func _refresh_actions() -> void:
	if _extra_actions == null:
		_extra_actions = ExplorationExtraActions.new(ExplorationContext.new(_dungeon, _player))
	var actions := _dungeon.actions_for(_player.tile, _player.facing_delta(), _player)
	actions.append_array(_extra_actions.build())
	# The MENU button is always there. DEV: it goes back to the scenario selection.
	actions.append(
		ExplorationAction.new(&"menu", "UI_ACTION_MENU", Callable(self, "_open_scenario_select"))
	)
	_action_menu.set_actions(actions)


## The affliction status banner (poison, disarray), top-left.
func _build_status() -> void:
	_status_label = Label.new()
	_status_label.position = Vector2(16, 16)
	_status_label.add_theme_color_override("font_color", Color(0.95, 0.75, 0.35))
	add_child(_status_label)


## Updates the status banner from the player's afflictions.
func _update_status() -> void:
	if _status_label == null or _player == null:
		return
	var aff = _player.get("affliction")
	if aff == null:
		_status_label.text = ""
		return
	var parts: Array[String] = []
	if aff.has_poison():
		parts.append(tr("UI_STATUS_POISON") % [aff.poison_turns, aff.poison_per_turn])
	if aff.has_disarray():
		parts.append(tr("UI_STATUS_DISARRAY") % aff.remaining_disarray())
	_status_label.text = "\n".join(parts)


## The one-off message banner, top-centre: what the dungeon has to SAY to the player — "the die
## rolls a 3, rivals appear all around" — as opposed to the status banner, which describes a
## situation that lasts.
func _build_message() -> void:
	_message_label = Label.new()
	_message_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_message_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_message_label.position.y = 56
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.72))
	_message_label.add_theme_font_size_override("font_size", 20)
	_message_label.modulate.a = 0.0
	add_child(_message_label)


## Shows a one-off message: full opacity for [constant MESSAGE_HOLD] seconds, then a fade. A new
## message replaces the previous one, cancelling any fade in progress.
func show_message(text: String) -> void:
	if _message_label == null:
		return
	_message_label.text = text
	_message_label.modulate.a = 1.0
	if _message_tween != null and _message_tween.is_valid():
		_message_tween.kill()
	_message_tween = create_tween()
	_message_tween.tween_interval(MESSAGE_HOLD)
	_message_tween.tween_property(_message_label, "modulate:a", 0.0, MESSAGE_FADE)


## The mini-map, anchored bottom-right (element 1 of the HUD).
func _build_minimap() -> void:
	var minimap := ExplorationMinimap.new()
	minimap.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	minimap.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	minimap.grow_vertical = Control.GROW_DIRECTION_BEGIN
	minimap.position = Vector2(-186, -186)
	add_child(minimap)


## DEV: back to the scenario selection screen, from the MENU button.
func _open_scenario_select() -> void:
	TransitionManager.change_scene(SCENARIO_SELECT)


# --------------------------------------------------------------------------
# The balance bar (narrow bridge)
# --------------------------------------------------------------------------


## A horizontal bar centred at the top: the cursor in the middle means balanced, at the edges
## means falling.
func _build_balance_bar() -> void:
	_balance_bar = ProgressBar.new()
	_balance_bar.show_percentage = false
	_balance_bar.min_value = 0.0
	_balance_bar.max_value = 1.0
	_balance_bar.step = 0.0
	_balance_bar.custom_minimum_size = Vector2(300, 18)
	_balance_bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_balance_bar.position = Vector2(-150, 24)
	_balance_bar.visible = false
	add_child(_balance_bar)


## Shows the current imbalance, in [-1, 1], where 0 is centred.
func show_balance(imbalance: float) -> void:
	_balance_bar.visible = true
	_balance_bar.value = clampf(0.5 + imbalance * 0.5, 0.0, 1.0)


func hide_balance() -> void:
	_balance_bar.visible = false


## Keyboard navigation for the action menu. Not modal: it does not block movement.
func _unhandled_input(event: InputEvent) -> void:
	if _action_menu == null or not _action_menu.has_actions():
		return
	# Shift+Tab BEFORE Tab: `is_action_pressed` ignores modifiers by default, so Shift+Tab would
	# fire `cycle_action` too. The reverse direction is tested with exact_match, which requires
	# the Shift key, and the forward one picks up the rest.
	if event.is_action_pressed("cycle_action_reverse", false, true):
		_action_menu.cycle(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("cycle_action"):
		_action_menu.cycle(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact"):
		_action_menu.confirm()
		# The state may have changed — a tile dug, a gateway opened, an ability spent — so
		# refresh.
		if _dungeon != null and _player != null:
			_refresh_actions()
		get_viewport().set_input_as_handled()
