## Bas d'écran de la rencontre : l'invite, la barre d'actions, la liste de sous-choix et la
## ligne de description.
##
## Purement WIDGET. Il ne connaît ni combattant, ni capacité, ni [EncounterManager] : on lui
## demande d'afficher un bouton et de rappeler un [Callable] quand on le presse. Le QUOI
## afficher — quelles actions, quelles cibles — reste dans [EncounterUi], où il est couplé à
## l'état de la rencontre, et c'est très bien ainsi.
##
## Pas de `class_name` (piège du cache de classes en CLI) : obtenu par `preload`.
extends RefCounted

## Icônes d'énergie posées sur les boutons de capacité. Jeu DISTINCT de celui de la
## timeline (`assets/sprites/ui/timeline/`), qui répond à un autre besoin de lecture.
const ENERGY_ICONS := {
	GameEnums.Energy.HEAT: "res://assets/sprites/ui/weaknesses/heat.png",
	GameEnums.Energy.FLUID: "res://assets/sprites/ui/weaknesses/fluid.png",
	GameEnums.Energy.CRYSTAL: "res://assets/sprites/ui/weaknesses/crystal.png",
	GameEnums.Energy.ARCANE: "res://assets/sprites/ui/weaknesses/arcane.png",
	GameEnums.Energy.TOXIC: "res://assets/sprites/ui/weaknesses/toxic.png",
}

## Largeur maximale d'une icône d'énergie sur un bouton, en pixels.
const ICON_WIDTH := 22

var _prompt: Label
var _description: Label
var _action_bar: HBoxContainer
var _options: VBoxContainer


func _init(
	prompt: Label, description: Label, action_bar: HBoxContainer, options: VBoxContainer
) -> void:
	_prompt = prompt
	_description = description
	_action_bar = action_bar
	_options = options


func set_prompt(text: String) -> void:
	_prompt.text = text


func set_description(text: String) -> void:
	_description.text = text
	_description.visible = text != ""


func show_bar(visible: bool) -> void:
	_action_bar.visible = visible


## Vide tout et referme le panneau : plus d'invite, plus de boutons, plus de description.
func clear() -> void:
	_action_bar.visible = false
	_description.visible = false
	_prompt.text = ""
	clear_bar()
	clear_options()


## Prépare une liste verticale de sous-choix : elle remplace la barre d'actions, qui n'a
## pas la place d'afficher une dizaine de capacités de front.
func begin_submenu() -> void:
	clear_options()
	clear_bar()
	_action_bar.visible = false
	set_description("")


func clear_options() -> void:
	for c in _options.get_children():
		_options.remove_child(c)
		c.queue_free()


func clear_bar() -> void:
	for c in _action_bar.get_children():
		_action_bar.remove_child(c)
		c.queue_free()


func add_option(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(on_press)
	_options.add_child(b)
	return b


## Bouton de la barre d'actions. Grisé mais TOUJOURS visible s'il est indisponible :
## « Unusable actions remain visible in the list, but greyed ».
func add_bar_action(text: String, enabled: bool, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text.to_upper()  # la casse est un parti pris visuel, pas une chaîne traduite
	b.flat = true
	b.disabled = not enabled
	b.pressed.connect(on_press)
	_action_bar.add_child(b)
	return b


## Remonte un bouton en tête de la barre d'actions. L'action « … » n'apparaît que si plus
## rien n'est jouable, et la doc la veut en PREMIER — d'où ce déplacement après coup.
func move_bar_action_first(btn: Button) -> void:
	_action_bar.move_child(btn, 0)


## Premier bouton cliquable de la BARRE (et non de la liste de sous-choix).
func first_enabled_bar_action() -> Button:
	return first_enabled(_action_bar)


func set_energy_icon(btn: Button, energy: GameEnums.Energy) -> void:
	if ENERGY_ICONS.has(energy):
		btn.icon = load(ENERGY_ICONS[energy])
		btn.add_theme_constant_override("icon_max_width", ICON_WIDTH)


func focus_first_option() -> void:
	var first := first_enabled(_options)
	if first:
		first.grab_focus()


## Premier bouton cliquable d'un conteneur, ou null s'il n'y en a aucun.
func first_enabled(container: Node) -> Button:
	for c in container.get_children():
		if c is Button and not c.disabled:
			return c
	return null
