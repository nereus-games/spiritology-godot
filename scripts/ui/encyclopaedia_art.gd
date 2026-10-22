## Pictures for the encyclopaedia: the species' icon and illustration, and the treatment an icon
## gets from its icon state (see `encyclopaedia_grid_logic.gd`).
##
## PLACEHOLDER art: the icon is the top of the species' encounter artwork, as in the turn order,
## and a species with no artwork yet gets a plain disc. A dedicated pictogram per species is for
## the artists.
##
## No `class_name` (the CLI class-cache trap): referenced by `preload`.
extends RefCounted

const GridLogic := preload("res://scripts/ui/encyclopaedia_grid_logic.gd")

const SPRITE_DIR := "res://assets/sprites/spirimonsters/"
const WEAKNESS_DIR := "res://assets/sprites/ui/timeline/"
const WEAKNESS_ICONS := {
	GameEnums.Energy.HEAT: WEAKNESS_DIR + "heat.png",
	GameEnums.Energy.FLUID: WEAKNESS_DIR + "fluid.png",
	GameEnums.Energy.CRYSTAL: WEAKNESS_DIR + "crystal.png",
	GameEnums.Energy.ARCANE: WEAKNESS_DIR + "arcane.png",
	GameEnums.Energy.TOXIC: WEAKNESS_DIR + "toxic.png",
}

const GRAY_SHADER := """
shader_type canvas_item;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float g = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(vec3(g), c.a) * COLOR;
}
"""

static var _gray_material: ShaderMaterial
static var _disc: Texture2D


## The full artwork, or null when the species has none yet.
static func illustration(species_id: StringName) -> Texture2D:
	var path := SPRITE_DIR + "%s.png" % species_id
	return load(path) if ResourceLoader.exists(path) else null


## A square from the top of the artwork, where the head is; a disc without artwork.
static func icon(species_id: StringName) -> Texture2D:
	var src := illustration(species_id)
	if src == null:
		return _placeholder_disc()
	var side := mini(src.get_width(), src.get_height())
	var atlas := AtlasTexture.new()
	atlas.atlas = src
	atlas.region = Rect2((src.get_width() - side) / 2.0, 0, side, side)
	return atlas


static func weakness_icon(energy: GameEnums.Energy) -> Texture2D:
	return load(WEAKNESS_ICONS[energy]) if WEAKNESS_ICONS.has(energy) else null


## Dresses `rect` for an icon state: hidden, black, grayscale or as it is.
static func apply_state(rect: TextureRect, state: GridLogic.IconState) -> void:
	rect.visible = state != GridLogic.IconState.NONE
	rect.material = _gray_material_shared() if state == GridLogic.IconState.GRAY else null
	rect.modulate = Color.BLACK if state == GridLogic.IconState.BLACK else Color.WHITE


static func _gray_material_shared() -> ShaderMaterial:
	if _gray_material == null:
		var shader := Shader.new()
		shader.code = GRAY_SHADER
		_gray_material = ShaderMaterial.new()
		_gray_material.shader = shader
	return _gray_material


static func _placeholder_disc() -> Texture2D:
	if _disc == null:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.88, 0.92])
		gradient.colors = PackedColorArray(
			[Color(0.7, 0.7, 0.78), Color(0.7, 0.7, 0.78), Color(0.7, 0.7, 0.78, 0.0)]
		)
		var tex := GradientTexture2D.new()
		tex.gradient = gradient
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = 128
		tex.height = 128
		_disc = tex
	return _disc
