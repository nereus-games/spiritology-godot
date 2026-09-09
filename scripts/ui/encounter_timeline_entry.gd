## Une case de la timeline (ordre du tour) d'une rencontre.
##
## Reproduit le gabarit du mockup Notion (User Interface / Encounters) : portrait
## encadré, et sous lui une réglette [DEN] – [faiblesse] – [ETH]. La case dont c'est le
## tour est agrandie et porte le nom du combattant au-dessus.
##
## Règle d'occultation (doc) : « rival's density and weakness aren't shown in timeline
## if they aren't in the encyclopaedia (yet) ». Un rival inconnu montre donc l'icône de
## faiblesse « unknown » et AUCUN chiffre — mais garde ses réglettes, pour que la case ne
## change pas de gabarit quand l'espèce devient connue en cours de rencontre.
## Volontairement SANS `class_name` : le cache des classes globales
## (`.godot/global_script_class_cache.cfg`) n'est régénéré que par l'éditeur, or le jeu
## se lance en ligne de commande. Un nouveau `class_name` y serait absent et planterait
## au chargement. L'UI de rencontre l'obtient donc par `preload`.
extends VBoxContainer

const SIZE_IDLE := 72.0
const SIZE_ACTIVE := 104.0

const COLOR_DEN := Color(0.94, 0.62, 0.24)   ## pastille orange (mockup)
const COLOR_ETH := Color(0.42, 0.82, 0.87)   ## pastille cyan (mockup)
const COLOR_FRAME_IDLE := Color(0.24, 0.24, 0.28)
const COLOR_FRAME_ACTIVE := Color(1, 1, 1)

## Fond de la case selon le camp (mockup « Encounter Rivals » : les personnages JOUEURS
## portent un petit fond de couleur, les rivaux un fond sombre neutre).
const COLOR_BG_PLAYER := Color(0.10, 0.24, 0.22)   ## teal doux = allié
const COLOR_BG_RIVAL := Color(0.06, 0.06, 0.08)

## Icônes de faiblesse de la TIMELINE (jeu d'icônes dédié du collègue). Toute case en a
## une : les 5 énergies, plus `none` (aucune faiblesse ce tour) et `unknown` (faiblesse
## cachée, ou rival pas encore dans l'encyclopédie). NB : le jeu d'icônes d'ÉNERGIE des
## capacités (menu) reste l'ancien, dans `ui/weaknesses/`.
const TL_DIR := "res://assets/sprites/ui/timeline/"
const WEAKNESS_ICONS := {
	GameEnums.Energy.HEAT: TL_DIR + "heat.png",
	GameEnums.Energy.FLUID: TL_DIR + "fluid.png",
	GameEnums.Energy.CRYSTAL: TL_DIR + "crystal.png",
	GameEnums.Energy.ARCANE: TL_DIR + "arcane.png",
	GameEnums.Energy.TOXIC: TL_DIR + "toxic.png",
}
const ICON_NONE := TL_DIR + "none.png"
const ICON_UNKNOWN := TL_DIR + "unknown.png"

var _name_label: Label
var _frame: PanelContainer
var _portrait: TextureRect
var _den_label: Label
var _eth_label: Label
var _weakness_icon: TextureRect

func _init() -> void:
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 2)

	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 13)
	add_child(_name_label)

	_frame = PanelContainer.new()
	_frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_portrait = TextureRect.new()
	_portrait.stretch_mode = TextureRect.STRETCH_SCALE
	# INDISPENSABLE : sans ça, la taille minimale du TextureRect est celle de la texture
	# source (800 px et plus), et `custom_minimum_size` ne la borne pas — c'est un
	# plancher, pas un plafond. La case de timeline prendrait toute la page.
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_frame.add_child(_portrait)
	add_child(_frame)

	var stats := HBoxContainer.new()
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	stats.add_theme_constant_override("separation", 2)
	_den_label = _make_pill(COLOR_DEN)
	stats.add_child(_den_label)

	# La faiblesse est TOUJOURS une pastille-icône : une des 5 énergies, `none` (aucune
	# faiblesse ce tour) ou `unknown` (cachée / rival hors encyclopédie).
	var badge := Control.new()
	badge.custom_minimum_size = Vector2(28, 28)
	_weakness_icon = TextureRect.new()
	_weakness_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_weakness_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_weakness_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	badge.add_child(_weakness_icon)
	stats.add_child(badge)

	_eth_label = _make_pill(COLOR_ETH)
	stats.add_child(_eth_label)
	add_child(stats)

func _make_pill(color: Color) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(38, 18)
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(0.08, 0.08, 0.1))
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(9)
	box.content_margin_left = 4
	box.content_margin_right = 4
	l.add_theme_stylebox_override("normal", box)
	return l

## Peuple la case. `known` = espèce enregistrée dans l'encyclopédie ; `active` = c'est
## son tour ; `weakness` = énergie faible ce tour (NONE si aucune).
##
## `rank` (1-based) n'est renseigné qu'en vue de test : il affiche « 2. ravbak » sur
## TOUTES les cases. En jeu, seule la case active porte un nom, comme au mockup — mais
## pour tester il faut pouvoir lire l'ordre d'action d'un coup d'œil.
func setup(fighter: EncounterFighter, known: bool, active: bool, weakness: GameEnums.Energy,
		rank: int = 0) -> void:
	var side := SIZE_ACTIVE if active else SIZE_IDLE
	_portrait.custom_minimum_size = Vector2(side, side)
	_portrait.texture = _portrait_texture(fighter)
	_portrait.modulate = Color(1, 1, 1) if not fighter.is_dissolved() else Color(0.35, 0.35, 0.4)

	var frame_box := StyleBoxFlat.new()
	# Fond coloré pour les joueurs, sombre pour les rivaux (mockup) : distinction de camp
	# lisible d'un coup d'œil, indépendamment de la case active (elle, agrandie + bord blanc).
	frame_box.bg_color = COLOR_BG_PLAYER if fighter.is_player else COLOR_BG_RIVAL
	frame_box.border_color = COLOR_FRAME_ACTIVE if active else COLOR_FRAME_IDLE
	frame_box.set_border_width_all(3 if active else 2)
	frame_box.set_corner_radius_all(4)
	_frame.add_theme_stylebox_override("panel", frame_box)

	if rank > 0:
		_name_label.text = "%d. %s" % [rank, fighter.display_name()]
		_name_label.visible = true
	else:
		_name_label.text = fighter.display_name() if active else ""
		_name_label.visible = active

	# Les chiffres du joueur sont toujours lisibles ; ceux d'un rival dépendent de
	# l'encyclopédie. Pastilles conservées mais vides, pour ne pas décaler la case.
	var show_numbers := fighter.is_player or known
	_den_label.text = str(fighter.den) if show_numbers else ""
	_eth_label.text = str(fighter.eth) if show_numbers else ""

	# `unknown` si la faiblesse est cachée (Anodyne Excess…) OU si le rival n'est pas encore
	# dans l'encyclopédie ; sinon l'icône de l'énergie faible, ou `none` s'il n'y en a aucune
	# à cette position ce tour. (Le second aspect — occultation encyclopédie — est déjà porté
	# par `known` ; on l'ignorera plus finement quand l'encyclopédie sera travaillée.)
	var show_weakness := (fighter.is_player or known) and not fighter.weakness_hidden
	if not show_weakness:
		_weakness_icon.texture = load(ICON_UNKNOWN)
	elif WEAKNESS_ICONS.has(weakness):
		_weakness_icon.texture = load(WEAKNESS_ICONS[weakness])
	else:
		_weakness_icon.texture = load(ICON_NONE)  # aucune faiblesse à cette position ce tour

## Portrait carré taillé dans le haut de l'illustration (là où est la tête), plutôt
## qu'une pleine planche écrasée dans un carré.
func _portrait_texture(fighter: EncounterFighter) -> Texture2D:
	var path := "res://assets/sprites/spirimonsters/%s.png" % fighter.species_id()
	if not ResourceLoader.exists(path):
		return null
	var src: Texture2D = load(path)
	var w := src.get_width()
	var h := src.get_height()
	var side: int = mini(w, h)
	var atlas := AtlasTexture.new()
	atlas.atlas = src
	atlas.region = Rect2((w - side) / 2.0, 0, side, side)
	return atlas
