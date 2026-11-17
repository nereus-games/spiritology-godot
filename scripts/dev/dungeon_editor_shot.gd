## Screenshot of the dungeon editor, for the look of it: the one thing no headless check judges.
##
## Opens the editor on a dungeon (the frozen lake by default), puts it in a fixed state and writes a
## PNG. A window opens briefly; no editor of Godot is involved.
##
## Run with:
##   godot --path . res://scenes/dev/dungeon_editor_shot.tscn -- <out.png> [floor] [tool] [more]
## `more` is any of: `select=AB24` (select that tile), `issue=3` (jump to the third issue),
## `size=1600x900` (the window), `edit` (make a few edits first, so the dirty mark and the undo
## buttons show), `locale=fr`, `slug=<dungeon>`, `zoom=24` and `dim=0` (hide the floor below).
## It reads the dungeon from `data/` and never writes to it.
extends Node

const Screen := preload("res://scenes/dev/dungeon_editor.tscn")
const Model := preload("res://scripts/dungeon/editor/dungeon_editor_model.gd")
const Util := preload("res://scripts/dungeon/editor/dungeon_editor_util.gd")

const SETTLE_FRAMES := 12


func _ready() -> void:
	_run()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "/tmp/dungeon_editor.png"
	var floor_y: int = int(args[1]) if args.size() > 1 else 0
	var tool: String = args[2] if args.size() > 2 else "select"
	var options := {}
	for a in args.slice(3):
		var kv: PackedStringArray = String(a).split("=", true, 1)
		options[kv[0]] = kv[1] if kv.size() == 2 else ""
	if options.has("locale"):
		TranslationServer.set_locale(options["locale"])
	if options.has("size"):
		var wh: PackedStringArray = String(options["size"]).split("x")
		get_window().size = Vector2i(int(wh[0]), int(wh[1]))
	await get_tree().process_frame
	var model := Model.new()
	model.load_dungeon(StringName(options.get("slug", "norgzevod_frozen_lake")))
	model.root = "user://never_saved/"
	var screen := Screen.instantiate()
	screen.model = model
	screen.navigate = false
	get_tree().root.add_child(screen)
	for _i in SETTLE_FRAMES:
		await get_tree().process_frame
	screen.set_floor(floor_y)
	if options.has("edit"):
		_edit(model, floor_y)
	screen.select_tool(tool)
	if options.has("dim"):
		screen.view.show_below = options["dim"] != "0"
	if options.has("zoom"):
		screen.view.zoom = float(options["zoom"])
	if options.has("select"):
		var tile = Model.Kinds.parse_tile(options["select"], floor_y)
		screen.select_tile(tile)
		screen.view.center_on(tile)
	screen.validate()
	if options.has("issue"):
		screen.jump_to_issue(int(options["issue"]))
	for _i in SETTLE_FRAMES:
		await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(out)
	print("[shot] dungeon editor -> %s (%s)" % [out, "OK" if err == OK else "err %d" % err])
	get_tree().quit(0 if err == OK else 1)


## A few edits that leave something to see: a wall, a trap, and a zone.
func _edit(model, y: int) -> void:
	model.paint_rect(Vector3i(12, y, 16), Vector3i(14, y, 17), &"wall")
	model.place(&"trap", Vector3i(15, y, 20), {"type": "poison"})
	model.create_zone("new_zone", ["safe"])
	model.zone_paint("new_zone", Util.rect_tiles(Vector3i(16, y, 22), Vector3i(19, y, 24)))
