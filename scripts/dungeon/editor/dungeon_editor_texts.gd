## The sentences of the dungeon editor, composed: the hover line, the validator's issues by their
## translation keys, the name of a kind, why an operation was refused. Static, so that the screen
## stays about wiring and the checks can ask the same questions the screen does.
##
## No `class_name` (the CLI class-cache trap): referenced by `preload`.
extends RefCounted

const Writer := preload("res://scripts/dungeon/dungeon_map_writer.gd")
const Validator := preload("res://scripts/dungeon/dungeon_validator.gd")


static func t(key: String) -> String:
	return String(TranslationServer.translate(key))


## A kind's translated name, or its identifier while it has none.
static func kind_label(kind: StringName) -> String:
	var key := "UI_DEV_EDITOR_KIND_" + String(kind).to_upper()
	var text := t(key)
	return String(kind) if text == key else text


static func terrain_name(terrain: StringName) -> String:
	return t("UI_DEV_EDITOR_TERRAIN_" + String(terrain).to_upper())


## Why the last operation of `model` was refused, from its error code.
static func refusal(code: String) -> String:
	if code.begins_with("BAD_PROP:"):
		return t("UI_DEV_EDITOR_ERR_BAD_PROP") % code.get_slice(":", 1)
	var key := "UI_DEV_EDITOR_ERR_" + code
	var text := t(key)
	return t("UI_DEV_EDITOR_ERR_GENERIC") % code if text == key else text


## The translated line for an issue; the validator's own English one when the code has no key yet.
static func issue_text(issue: Dictionary) -> String:
	var key := "UI_DEV_ISSUE_" + String(issue["code"])
	var text := t(key)
	if text == key:
		return Validator.message(issue)
	var args: Array = issue["args"]
	if args.size() > 0 and text.contains("%"):
		text = text % args
	return text


## A flat button for an issue, coloured by severity (waived ones apart), wrapping its text.
static func issue_button(issue: Dictionary) -> Button:
	var text := issue_text(issue)
	var where := ""
	if issue["tile"] != null:
		var tile: Vector3i = issue["tile"]
		where = "%s@%d  " % [Writer.cell_name(tile.x, tile.z), tile.y]
	var color := Color(1.0, 0.5, 0.45)
	var tag := t("UI_DEV_EDITOR_SEVERITY_ERROR")
	if issue["severity"] == "warning":
		color = Color(1.0, 0.85, 0.35)
		tag = t("UI_DEV_EDITOR_SEVERITY_WARNING")
	if issue.has("waived"):
		color = Color(0.66, 0.66, 0.58)
		tag = t("UI_DEV_EDITOR_SEVERITY_WAIVED")
		text += "  [%s]" % (t("UI_DEV_EDITOR_ISSUE_WAIVED") % issue["waived"])
	var b := Button.new()
	b.text = "%s  %s%s" % [tag, where, text]
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = str(issue["source"])
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(state, color)
	return b


## What the hover line says about a tile: its cell name, floor, terrain, and what is on it.
static func describe(model, tile: Vector3i) -> String:
	var parts: Array[String] = [
		Writer.cell_name(tile.x, tile.z),
		t("UI_DEV_EDITOR_FLOOR") % tile.y,
		terrain_name(model.terrain_of(tile)),
	]
	var plan = model.plan
	if plan.has_entrance and plan.entrance == tile:
		parts.append(t("UI_DEV_EDITOR_HOVER_ENTRANCE"))
	if plan.exits.has(tile):
		parts.append(t("UI_DEV_EDITOR_HOVER_EXIT"))
	var kinds: Array[String] = []
	for p in model.placements_at(tile):
		kinds.append(kind_label(p["kind"]))
	if not kinds.is_empty():
		parts.append(", ".join(kinds))
	var zones: Array[String] = model.zones_at(tile)
	if not zones.is_empty():
		parts.append(t("UI_DEV_EDITOR_HOVER_ZONE") % ", ".join(zones))
	var note: String = model.tile_props(tile).get("note", "")
	if note == "":
		for p in model.placements_at(tile):
			note = p["props"].get("note", note)
	if note != "":
		parts.append(t("UI_DEV_EDITOR_HOVER_NOTE") % note)
	return "  ·  ".join(parts)
