## Screenshot of the assembly screen, from the command line.
##
## Run with:
##   Godot --path . res://scenes/dev/encyclopaedia_assembly_shot.tscn -- <out.png> [mode]
##   `initial` (default) shows the desk as first opened, new fragments lying in their area;
##   `manipulating` has a fragment held, with the grid and a stain; `damaged` shows damaged and
##   stained fragments on the desk, and `completed` a finished page.
## Everything is seeded: the same code gives the same image. No --headless: a rendering context
## is needed, so a window opens briefly.
extends Node

const Screen := preload("res://scenes/ui/encyclopaedia_assembly.tscn")
const Fragment := preload("res://scripts/encyclopaedia/puzzle_fragment.gd")

const SPECIES := &"kalilk"
## Frames given to the UI to settle: font and layout.
const SETTLE_FRAMES := 20


func _ready() -> void:
	_run()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "/tmp/assembly.png"
	var mode: String = args[1] if args.size() > 1 else "initial"

	await get_tree().process_frame
	GameSession.encyclopaedia.clear()
	if mode == "completed":
		GameSession.encyclopaedia.add_ifp(SPECIES, 99)
		GameSession.encyclopaedia.set_arranged(SPECIES, false, 33)
		GameSession.encyclopaedia.mark_assembled(SPECIES)
	else:
		GameSession.encyclopaedia.add_ifp(SPECIES, 60)
		GameSession.encyclopaedia.set_arranged(SPECIES, false, 6 if mode != "initial" else 0)
	var screen := Screen.instantiate()
	screen.species_id = SPECIES
	get_tree().root.add_child(screen)
	for i in SETTLE_FRAMES:
		await get_tree().process_frame

	var logic: Variant = screen.logic
	match mode:
		"manipulating":
			_lay_loose(logic, [[6, Vector2i(14, 17), 0], [7, Vector2i(24, 17), 3]])
			logic.select(8)
			logic.step(Vector2i.LEFT)
			logic.turn(true)
			for i in 6:
				logic.step(Vector2i.UP)
			logic.desk.fragment(8).stain = 0.55
		"damaged":
			_lay_loose(logic, [[6, Vector2i(14, 17), 0], [7, Vector2i(24, 17), 3]])
			_lay_loose(logic, [[8, Vector2i(34, 17), 1], [9, Vector2i(10, 22), 2]])
			logic.desk.fragment(6).damaged = true
			logic.desk.fragment(7).damaged = true
			logic.desk.fragment(7).stain = 0.85
			logic.desk.fragment(8).stain = 0.4
			logic.desk.fragment(2).damaged = true
			logic.desk.fragment(3).damaged = true
	screen.refresh(false)
	for i in SETTLE_FRAMES:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	print("[shot] %s -> %s" % [mode, out])
	get_tree().quit()


## Puts the fragments `[id, tile, quarter turns]` on the desk.
func _lay_loose(logic: Variant, list: Array) -> void:
	for entry in list:
		logic.desk.restore_fragment(entry[0], Fragment.Area.DESK, entry[1], entry[2], false, 0.0)
