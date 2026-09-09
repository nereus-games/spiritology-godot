## Menu des actions contextuelles d'exploration (élément 3 du HUD, doc Notion « User
## Interface »).
##
## Affiche la liste des [ExplorationAction] disponibles pour le joueur (fournies par
## [method DungeonManager.actions_for] : Dig, Recycle, Examine, Meditate, ouvrir une porte,
## rafraîchir, traverser un mur fissuré…). Navigation au clavier : cycler la sélection puis
## valider ; valider invoque le `callable` de l'action sélectionnée. Non modal (le déplacement
## reste possible), volontairement construit PAR CODE et minimal — le rendu final (icônes
## rondes, sous-menu USE/CANCEL, alignement sur l'icône présélectionnée) se peaufinera en
## moteur.
##
## Pas de `class_name` (piège du cache CLI) : référencé par `preload`.
extends Control

## Émis quand le joueur valide une action (après invocation de son callable).
signal action_confirmed(id: StringName)

const SELECTED_COLOR := Color(1.0, 0.9, 0.4)
const NORMAL_COLOR := Color(0.9, 0.75, 0.75)

var _actions: Array = []
var _selected := 0
var _rows: Array[Label] = []
var _box: VBoxContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 4)
	# Ancré en bas à gauche, croît vers le HAUT : la dernière entrée (MENU) reste près du bas,
	# les actions contextuelles s'empilent au-dessus, toutes visibles.
	_box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_box.position += Vector2(20, -40)
	add_child(_box)
	visible = false


## Vrai si au moins une action est proposée.
func has_actions() -> bool:
	return not _actions.is_empty()


## Id de l'action actuellement sélectionnée (&"" si aucune).
func selected_id() -> StringName:
	if _actions.is_empty():
		return &""
	return _actions[_selected].id


## Remplace la liste d'actions. Ne reconstruit que si les ids ont changé (évite le
## scintillement à chaque frame). Conserve la sélection sur le même id si possible.
func set_actions(actions: Array) -> void:
	if _same_ids(actions):
		return
	var previously := selected_id()
	_actions = actions
	_selected = 0
	for i in _actions.size():
		if _actions[i].id == previously:
			_selected = i
			break
	_rebuild()


## Cycle la sélection de `step` positions (avec bouclage).
func cycle(step: int) -> void:
	if _actions.is_empty():
		return
	_selected = wrapi(_selected + step, 0, _actions.size())
	_update_highlight()


## Valide l'action sélectionnée : invoque son callable et émet [signal action_confirmed].
## Retourne false si aucune action n'est disponible.
func confirm() -> bool:
	if _actions.is_empty():
		return false
	var action = _actions[_selected]
	if action.callable.is_valid():
		action.callable.call()
	action_confirmed.emit(action.id)
	return true


func _same_ids(actions: Array) -> bool:
	if actions.size() != _actions.size():
		return false
	for i in actions.size():
		if actions[i].id != _actions[i].id:
			return false
	return true


func _rebuild() -> void:
	for child in _box.get_children():
		child.queue_free()
	_rows.clear()
	for action in _actions:
		var label := Label.new()
		label.text = _label_for(action)
		_box.add_child(label)
		_rows.append(label)
	visible = not _actions.is_empty()
	_update_highlight()


## Libellé affiché : traduction de `label_key` si disponible, sinon l'id « joliment » (repli
## tant que les clés UI_ACTION_* ne sont pas dans les .po).
func _label_for(action) -> String:
	var t := String(TranslationServer.translate(action.label_key))
	if t == action.label_key:
		t = String(action.id).capitalize()
	return t


func _update_highlight() -> void:
	for i in _rows.size():
		_rows[i].add_theme_color_override(
			"font_color", SELECTED_COLOR if i == _selected else NORMAL_COLOR
		)
