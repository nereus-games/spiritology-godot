## Validates the dungeons in `data/dungeons/<slug>/` and prints every issue. Exits 1 when any
## dungeon has an error; warnings alone do not fail it.
##
## Run with: tools/validate_dungeons.sh [slug…]
## As a start scene rather than --script; see geometry_check.gd.
extends Node

const Parser := preload("res://scripts/dungeon/dungeon_map_parser.gd")
const Validator := preload("res://scripts/dungeon/dungeon_validator.gd")


func _ready() -> void:
	await get_tree().process_frame
	var wanted: Array[StringName] = []
	for arg in OS.get_cmdline_user_args():
		wanted.append(StringName(arg))
	var slugs := wanted if not wanted.is_empty() else Parser.slugs()
	var failed := 0
	for slug in slugs:
		var plan := Parser.load_slug(slug)
		var issues := Validator.new().validate(plan, GameData.dungeon(slug))
		var errors := Validator.error_count(issues)
		print("%s: %d error(s), %d warning(s)" % [slug, errors, issues.size() - errors])
		for issue in issues:
			print("  " + Validator.format_issue(issue))
		if errors > 0:
			failed += 1
	if slugs.is_empty():
		print("No dungeon to validate.")
	get_tree().quit(1 if failed > 0 else 0)
