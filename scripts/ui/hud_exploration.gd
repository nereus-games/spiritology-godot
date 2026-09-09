## HUD minimal d'exploration : jauges DEN/ETH du duo + menu d'actions contextuelles.
##
## Volontairement construit PAR CODE et minimal (placeholder ajustable). Affiche les deux
## emplacements du duo ([enum GameSession.PartySlot]) avec nom, barre DEN, barre ETH et
## texte « courant/max » (élément 2 de la doc), et un menu d'actions contextuelles en bas à
## gauche (élément 3) alimenté par [method DungeonManager.actions_for] selon la case et
## l'orientation du joueur. Navigation : `cycle_action` (Tab) cycle, `cycle_action_reverse`
## (Maj+Tab) cycle à l'envers, `interact` (Espace/Entrée) valide. Se met à jour en direct
## via les signaux DEN/ETH de [GameSession].
## TODO (doc Notion « User Interface ») : mini-map (élément 1), pile des capacités
## d'exploration connues (élément 4) avec sous-menu USE/CANCEL, disposition finale (DEN/ETH
## en bas-centre, icônes rondes).
extends CanvasLayer

const ExplorationActionMenu := preload("res://scripts/ui/exploration_action_menu.gd")
const ExplorationContext := preload("res://scripts/exploration/abilities/exploration_context.gd")
const ExplorationExtraActions := preload("res://scripts/exploration/exploration_extra_actions.gd")
const ExplorationAction := preload("res://scripts/exploration/exploration_action.gd")
const ExplorationMinimap := preload("res://scripts/ui/exploration_minimap.gd")

## DEV : écran de sélection des scénarios de test (cible du bouton MENU, temporaire).
const SCENARIO_SELECT := "res://scenes/dev/scenario_select.tscn"

## Emplacements affichés, dans l'ordre (principal puis coéquipier).
const SLOTS: Array[GameSession.PartySlot] = [
	GameSession.PartySlot.MAIN,
	GameSession.PartySlot.TEAMMATE,
]

const DEN_COLOR := Color(0.85, 0.27, 0.30)  ## densité (vie)
const ETH_COLOR := Color(0.30, 0.62, 0.90)  ## éther (énergie)

var _name_label: Dictionary = {}  # slot -> Label
var _den_bar: Dictionary = {}  # slot -> ProgressBar
var _eth_bar: Dictionary = {}  # slot -> ProgressBar
var _den_text: Dictionary = {}  # slot -> Label
var _eth_text: Dictionary = {}  # slot -> Label

var _action_menu: Control
var _dungeon: DungeonManager
var _player: Node
var _extra_actions  # ExplorationExtraActions (capacités + objets d'exploration)

var _balance_bar: ProgressBar
var _status_label: Label

## Bandeau de messages ponctuels (résultat d'un dieverting…) et son fondu de sortie.
var _message_label: Label
var _message_tween: Tween

## Temps d'affichage plein (s) d'un message, puis durée du fondu.
const MESSAGE_HOLD := 4.0
const MESSAGE_FADE := 1.0


func _ready() -> void:
	layer = 10  # au-dessus de la 3D, sous l'overlay de rencontre (TransitionManager)
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


## Construit l'arborescence d'UI (jauges DEN/ETH côte à côte, en bas au centre — doc UI).
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
	row.position.y = -12  # 12 px au-dessus du bord inférieur
	root.add_child(row)

	for slot in SLOTS:
		row.add_child(_build_slot(slot))


## Construit le panneau d'un emplacement et mémorise ses widgets.
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


## Construit une ligne « libellé + barre + texte courant/max » et mémorise barre & texte.
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


## Rafraîchit intégralement un emplacement (nom + barres + textes).
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


## Nom affiché : nom traduit de l'espèce de l'emplacement, sinon un repli générique.
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
# Menu d'actions contextuelles (élément 3)
# --------------------------------------------------------------------------


## Construit le menu d'actions (plein écran ; la liste elle-même s'ancre en bas à gauche et
## croît vers le haut, de sorte que toutes les entrées restent visibles).
func _build_action_menu() -> void:
	_action_menu = ExplorationActionMenu.new()
	_action_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	_action_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_action_menu)


## Interroge chaque frame les actions contextuelles disponibles quand le joueur est au repos
## et met à jour le menu. (Résout paresseusement le donjon et le joueur : le HUD peut être
## prêt avant eux.)
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


## Recompose le menu : actions de mécanismes (case + case regardée) + capacités et objets
## d'exploration (via un [ExplorationExtraActions] persistant, dont les callables restent
## valides tant que le menu les affiche).
func _refresh_actions() -> void:
	if _extra_actions == null:
		_extra_actions = ExplorationExtraActions.new(ExplorationContext.new(_dungeon, _player))
	var actions := _dungeon.actions_for(_player.cell, _player.facing_delta(), _player)
	actions.append_array(_extra_actions.build())
	# Bouton MENU toujours présent (DEV : renvoie à la sélection de scénarios).
	actions.append(
		ExplorationAction.new(&"menu", "UI_ACTION_MENU", Callable(self, "_open_scenario_select"))
	)
	_action_menu.set_actions(actions)


## Bandeau d'état des afflictions (poison / disarray), en haut à gauche.
func _build_status() -> void:
	_status_label = Label.new()
	_status_label.position = Vector2(16, 16)
	_status_label.add_theme_color_override("font_color", Color(0.95, 0.75, 0.35))
	add_child(_status_label)


## Met à jour le bandeau d'état depuis les afflictions du joueur.
func _update_status() -> void:
	if _status_label == null or _player == null:
		return
	var aff = _player.get("affliction")
	if aff == null:
		_status_label.text = ""
		return
	var parts: Array[String] = []
	if aff.has_poison():
		parts.append("☠ Poison : %d tour(s) (-%d DEN)" % [aff.poison_turns, aff.poison_per_turn])
	if aff.has_disarray():
		parts.append("✦ Désorienté : %d mouvement(s)" % aff.remaining_disarray())
	_status_label.text = "\n".join(parts)


## Bandeau de messages ponctuels, centré en haut : ce que le donjon a à DIRE au joueur
## (« Le cubimprévu fait 3 — des rivaux surgissent tout autour »), par opposition au bandeau
## d'état qui, lui, décrit une situation qui dure.
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


## Affiche un message ponctuel : plein pendant [constant MESSAGE_HOLD] s, puis fondu. Un
## nouveau message remplace le précédent (le fondu en cours est annulé).
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


## Mini-map ancrée en bas à droite (élément 1 du HUD).
func _build_minimap() -> void:
	var minimap := ExplorationMinimap.new()
	minimap.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	minimap.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	minimap.grow_vertical = Control.GROW_DIRECTION_BEGIN
	minimap.position = Vector2(-186, -186)
	add_child(minimap)


## DEV : retour à l'écran de sélection des scénarios (bouton MENU).
func _open_scenario_select() -> void:
	TransitionManager.change_scene(SCENARIO_SELECT)


# --------------------------------------------------------------------------
# Barre d'équilibre (pont étroit)
# --------------------------------------------------------------------------


## Barre horizontale centrée haut : le curseur au centre = équilibre, aux bords = chute.
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


## Affiche le déséquilibre courant ∈ [-1, 1] (0 = centré).
func show_balance(imbalance: float) -> void:
	_balance_bar.visible = true
	_balance_bar.value = clampf(0.5 + imbalance * 0.5, 0.0, 1.0)


func hide_balance() -> void:
	_balance_bar.visible = false


## Navigation clavier du menu d'actions (non modal : ne bloque pas le déplacement).
func _unhandled_input(event: InputEvent) -> void:
	if _action_menu == null or not _action_menu.has_actions():
		return
	# Maj+Tab AVANT Tab : `is_action_pressed` ignore les modificateurs par défaut, donc
	# Maj+Tab déclencherait aussi `cycle_action`. Le sens inverse est testé en exact_match
	# (la touche Maj est exigée), le sens avant récupère le reste.
	if event.is_action_pressed("cycle_action_reverse", false, true):
		_action_menu.cycle(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("cycle_action"):
		_action_menu.cycle(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact"):
		_action_menu.confirm()
		# L'état a pu changer (case creusée, porte ouverte, capacité utilisée…) : rafraîchir.
		if _dungeon != null and _player != null:
			_refresh_actions()
		get_viewport().set_input_as_handled()
