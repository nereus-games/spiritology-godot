## Screenshot of the encounter UI, without having to walk up to a rival.
##
## In game the encounter is only reachable as an overlay from exploration, on contact with a
## rival, and so cannot be checked in a single command. This script opens it directly, leaves the
## player at the moment of choosing, and writes a PNG.
##
## Run with: Godot --path . res://scenes/dev/encounter_shot.tscn -- <out.png> [duo] [rivals]
##   duo and rivals are comma-separated slugs; defaults below.
## No --headless: a rendering context is needed, so a window opens briefly.
##
## This is the ONLY visual check on `encounter_ui.gd`, which no headless check covers: the
## encounter loop is tested without its screen.
extends Node

const ENCOUNTER := preload("res://scenes/encounter/encounter.tscn")

const DEFAULT_PLAYERS := "kalilk,fliritus"
const DEFAULT_RIVALS := "ravbak,skorpis"

## How many frames the UI is given to settle: font, layout, turn order.
const SETTLE_FRAMES := 40

## The seed forced on the encounter. Without it the turn order is random, and two shots of the
## SAME code differ, which makes A/B comparison useless.
const SEED := 20260909


func _ready() -> void:
	_run()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "/tmp/encounter.png"
	var players: String = args[1] if args.size() > 1 else DEFAULT_PLAYERS
	var rivals: String = args[2] if args.size() > 2 else DEFAULT_RIVALS

	await get_tree().process_frame  # let the root finish installing its children
	var ui := ENCOUNTER.instantiate()
	get_tree().root.add_child(ui)
	ui.begin(players.split(","), rivals.split(","), {}, [], SEED)

	for _i in range(SETTLE_FRAMES):
		await get_tree().process_frame

	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(out)
	print("[shot] encounter -> %s (%s)" % [out, "OK" if err == OK else "err %d" % err])
	get_tree().quit(0 if err == OK else 1)
