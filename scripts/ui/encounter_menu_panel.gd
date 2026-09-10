## The encounter's bottom panel: the prompt, the action bar, the sub-choice list and the
## description line.
##
## Purely a WIDGET. It knows nothing of individuals, abilities or the [EncounterManager] — you
## ask it to show a button and call back when pressed. WHICH buttons, and which targets,
## stays in the encounter UI where it is coupled to the state of the encounter, and that is
## where it belongs.
##
## No `class_name`: preloaded instead, for the reason in CLAUDE.md.
extends RefCounted

## Energy icons for ability buttons. A DIFFERENT set from the turn order's, which answers
## a different reading need.
const ENERGY_ICONS := {
	GameEnums.Energy.HEAT: "res://assets/sprites/ui/weaknesses/heat.png",
	GameEnums.Energy.FLUID: "res://assets/sprites/ui/weaknesses/fluid.png",
	GameEnums.Energy.CRYSTAL: "res://assets/sprites/ui/weaknesses/crystal.png",
	GameEnums.Energy.ARCANE: "res://assets/sprites/ui/weaknesses/arcane.png",
	GameEnums.Energy.TOXIC: "res://assets/sprites/ui/weaknesses/toxic.png",
}

## Maximum width of an energy icon on a button, in pixels.
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


## Empties the panel completely: no prompt, no buttons, no description.
func clear() -> void:
	_action_bar.visible = false
	_description.visible = false
	_prompt.text = ""
	clear_bar()
	clear_options()


## Switches to a vertical list of sub-choices, replacing the action bar — which has no room
## for a dozen abilities side by side.
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


## A button on the action bar. Greyed but ALWAYS visible when unavailable:
## « Unusable actions remain visible in the list, but greyed ».
func add_bar_action(text: String, enabled: bool, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text.to_upper()  # a visual choice, not part of the translated string
	b.flat = true
	b.disabled = not enabled
	b.pressed.connect(on_press)
	_action_bar.add_child(b)
	return b


## Moves a button to the front of the bar. The "…" action only appears when nothing else
## is playable, and the doc wants it FIRST — hence moving it after the fact.
func move_bar_action_first(btn: Button) -> void:
	_action_bar.move_child(btn, 0)


## First clickable button on the BAR, as opposed to the sub-choice list.
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


## First clickable button in a container, or null if there is none.
func first_enabled(container: Node) -> Button:
	for c in container.get_children():
		if c is Button and not c.disabled:
			return c
	return null
