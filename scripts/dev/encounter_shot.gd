## Capture d'écran de l'UI de rencontre, sans avoir à marcher jusqu'à un rival.
##
## En jeu, la rencontre n'est atteignable qu'en overlay depuis l'exploration, au contact
## d'un rival — donc invérifiable en une commande. Ce script l'ouvre directement, laisse le
## joueur au moment du choix, et écrit un PNG.
##
## Lancé par : Godot --path . res://scenes/dev/encounter_shot.tscn -- <sortie.png> [duo] [rivaux]
##   duo, rivaux : slugs séparés par des virgules (défauts ci-dessous).
## Pas de --headless : il faut un contexte de rendu (une fenêtre s'ouvre brièvement).
##
## C'est le SEUL contrôle visuel de `encounter_ui.gd`, qu'aucune vérification headless ne
## couvre : la boucle de rencontre est testée sans son écran.
extends Node

const ENCOUNTER := preload("res://scenes/encounter/encounter.tscn")

const DEFAULT_PLAYERS := "kalilk,fliritus"
const DEFAULT_RIVALS := "ravbak,skorpis"

## Nombre de frames laissées à l'UI pour se poser (police, disposition, timeline).
const SETTLE_FRAMES := 40


func _ready() -> void:
	_run()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "/tmp/encounter.png"
	var players: String = args[1] if args.size() > 1 else DEFAULT_PLAYERS
	var rivals: String = args[2] if args.size() > 2 else DEFAULT_RIVALS

	await get_tree().process_frame  # la racine finit d'installer ses enfants
	var ui := ENCOUNTER.instantiate()
	get_tree().root.add_child(ui)
	ui.begin(players.split(","), rivals.split(","))

	for _i in range(SETTLE_FRAMES):
		await get_tree().process_frame

	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(out)
	print("[shot] rencontre -> %s (%s)" % [out, "OK" if err == OK else "err %d" % err])
	get_tree().quit(0 if err == OK else 1)
