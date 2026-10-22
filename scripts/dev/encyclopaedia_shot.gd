## Screenshot of the encyclopaedia screen, from the command line.
##
## Run with: Godot --path . res://scenes/dev/encyclopaedia_shot.tscn -- <out.png> [grid|page|forlorn] [species]
##   `grid` (default) shows the grid with the selector on `species`; `page` opens that species'
##   page, `forlorn` its second tab. The progress is the dev sample, so every icon state shows.
## No --headless: a rendering context is needed, so a window opens briefly.
extends Node

const Screen := preload("res://scripts/ui/encyclopaedia_screen.gd")
const Sample := preload("res://scripts/dev/encyclopaedia_sample.gd")

## Frames given to the UI to settle: font and layout.
const SETTLE_FRAMES := 20

## Placeholder-order species with sample progress, for the default shot.
const DEFAULT_SPECIES := &"kalilk"


func _ready() -> void:
	_run()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "/tmp/encyclopaedia.png"
	var mode: String = args[1] if args.size() > 1 else "grid"
	var species := StringName(args[2]) if args.size() > 2 else DEFAULT_SPECIES

	await get_tree().process_frame
	Sample.fill()
	var screen := Screen.new()
	screen.start_species = species
	get_tree().root.add_child(screen)
	await get_tree().process_frame
	if mode != "grid":
		screen.call("_show_page", species)
		if mode == "forlorn":
			screen._page.set_forlorn_tab(true)
	for i in SETTLE_FRAMES:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	print("[shot] %s %s -> %s" % [mode, species, out])
	get_tree().quit()
