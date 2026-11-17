## Preview and inspection of a dungeon from the command line: `dump`, `png`, `stats`, `walk`.
##
## Run with: tools/dungeon_preview.sh <dump|png|stats|walk> <slug> [options]
## As a start scene rather than --script; see geometry_check.gd. The logic lives in
## `scripts/dungeon/dungeon_{dump,png,stats,walk}.gd`; this only reads the arguments and prints.
##
## Exit code: 0 on success, 1 when `walk` finds the validator and the engine disagreeing, 2 for a
## usage error.
extends Node

const Parser := preload("res://scripts/dungeon/dungeon_map_parser.gd")
const Validator := preload("res://scripts/dungeon/dungeon_validator.gd")
const View := preload("res://scripts/dungeon/dungeon_view.gd")
const Dump := preload("res://scripts/dungeon/dungeon_dump.gd")
const Png := preload("res://scripts/dungeon/dungeon_png.gd")
const Stats := preload("res://scripts/dungeon/dungeon_stats.gd")
const Walk := preload("res://scripts/dungeon/dungeon_walk.gd")
const Loader := preload("res://scripts/dungeon/dungeon_loader.gd")

const USAGE := """usage: tools/dungeon_preview.sh <command> <slug> [options]

  dump  <slug> [--floor N] [--zone NAME] [--rect AB24:AF30] [--issues] [--list]
        an ASCII rendering of the floors, with a legend
  png   <slug> --out DIR [--scale N] [--floor N] [--issues]
        one PNG per floor plus all.png, a contact sheet
  stats <slug> [--json]
        tile and placement counts, spawn points, reachability, issues
  walk  <slug>
        walks the real engine from the entrance and compares it with the validator;
        exits 1 on any disagreement"""

const COMMANDS := ["dump", "png", "stats", "walk"]
## Options that take a value.
const VALUED := ["--floor", "--zone", "--rect", "--out", "--scale"]
const FLAGS := ["--issues", "--list", "--json"]


func _ready() -> void:
	await get_tree().process_frame
	get_tree().quit(await _run(OS.get_cmdline_user_args()))


func _run(args: PackedStringArray) -> int:
	if args.is_empty() or args[0] in ["-h", "--help", "help"]:
		print(USAGE)
		return 0 if not args.is_empty() else 2
	var parsed := _parse(args)
	if parsed.has("error"):
		return _fail(parsed["error"])
	var command: String = parsed["command"]
	var slug: StringName = parsed["slug"]
	var options: Dictionary = parsed["options"]
	var plan := Parser.load_slug(slug)
	var config = GameData.dungeon(slug)
	match command:
		"dump":
			return _dump(plan, config, options)
		"png":
			return _png(plan, config, options)
		"stats":
			return _stats(plan, config, options)
	return await _walk(plan, config)


## `{command, slug, options}` from the arguments, or `{error}` saying what is wrong with them.
func _parse(args: PackedStringArray) -> Dictionary:
	var command := args[0]
	if not COMMANDS.has(command):
		return {"error": "unknown command '%s'" % command}
	if args.size() < 2 or args[1].begins_with("--"):
		return {"error": "%s needs a dungeon slug" % command}
	var slug := StringName(args[1])
	if not Parser.slugs().has(slug):
		return {"error": "no dungeon '%s' (have: %s)" % [slug, ", ".join(Parser.slugs())]}
	var options := {}
	var i := 2
	while i < args.size():
		var arg := args[i]
		if VALUED.has(arg) and i + 1 < args.size():
			options[arg.substr(2)] = args[i + 1]
			i += 2
		elif FLAGS.has(arg):
			options[arg.substr(2)] = true
			i += 1
		else:
			var why := "%s needs a value" if VALUED.has(arg) else "unknown option '%s'"
			return {"error": why % arg}
	var typed = _typed(options)
	if typed is String:
		return {"error": typed}
	return {"command": command, "slug": slug, "options": typed}


## The options with their real types, or an error message.
func _typed(options: Dictionary):
	var out := options.duplicate()
	for key in ["floor", "scale"]:
		if options.has(key):
			if not String(options[key]).is_valid_int():
				return "--%s wants a whole number, not '%s'" % [key, options[key]]
			out[key] = int(options[key])
	if out.has("scale") and out["scale"] < 4:
		return "--scale must be at least 4"
	if options.has("rect"):
		var rect = View.parse_rect(String(options["rect"]))
		if rect == null:
			return "--rect wants two cell names such as AB24:AF30, not '%s'" % options["rect"]
		out["rect"] = rect
	return out


func _fail(message: String) -> int:
	printerr("dungeon_preview: " + message)
	printerr("run with `help` for the usage")
	return 2


func _dump(plan, config, options: Dictionary) -> int:
	var why := Dump.problem(plan, options)
	if why != "":
		return _fail(why)
	if options.has("issues"):
		options["issues"] = Validator.new().validate(plan, config)
	print(Dump.render(plan, options).trim_suffix("\n"))
	return 0


func _png(plan, config, options: Dictionary) -> int:
	if not options.has("out"):
		return _fail("png needs --out DIR: nothing is written anywhere by default")
	if options.has("floor") and not View.floors(plan).has(options["floor"]):
		return _fail("no floor %d in %s" % [options["floor"], plan.slug])
	var dir := String(options["out"])
	if DirAccess.make_dir_recursive_absolute(dir) != OK:
		return _fail("cannot create the directory %s" % dir)
	var issues = Validator.new().validate(plan, config) if options.has("issues") else null
	var scale: int = options.get("scale", Png.DEFAULT_SCALE)
	var images := {}
	for y in View.floors(plan):
		if options.has("floor") and options["floor"] != y:
			continue
		images[y] = Png.render_floor(plan, y, {"scale": scale, "issues": issues})
	for y in images:
		var path := dir.path_join("floor_%d.png" % y)
		if images[y].save_png(path) != OK:
			return _fail("cannot write %s" % path)
		print("wrote %s  (%dx%d)" % [path, images[y].get_width(), images[y].get_height()])
	if not options.has("floor"):
		var sheet := Png.contact_sheet(images)
		var path := dir.path_join("all.png")
		if sheet.save_png(path) != OK:
			return _fail("cannot write %s" % path)
		print("wrote %s  (%dx%d)" % [path, sheet.get_width(), sheet.get_height()])
	return 0


func _stats(plan, config, options: Dictionary) -> int:
	var issues := Validator.new().validate(plan, config)
	var reached := Validator.new().reachable_from_entrance(plan)
	var stats := Stats.compute(plan, issues, reached)
	if options.has("json"):
		print(Stats.to_json(stats))
	else:
		print(Stats.format_text(stats).trim_suffix("\n"))
	return 0


func _walk(plan, config) -> int:
	var dm := DungeonManager.new()
	add_child(dm)
	var built := Loader.build_plan(plan, dm, config)
	var report := Walk.walk(plan, dm)
	report["start"] = built["start"]
	print(Walk.format_report(plan, report).trim_suffix("\n"))
	dm.queue_free()
	return 1 if report["disagreements"] > 0 else 0
